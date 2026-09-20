#!/usr/bin/env ruby
# frozen_string_literal: true

# App Store Connect にスクリーンショットをアップロードする。
#
# 編集可能な App Store バージョンを探し、その全ロケールについて、
# 対象サイズの既存スクリーンショットを削除してから差し替える。
#
# 必要な環境変数:
#   ASC_KEY_ID        App Store Connect API キーの Key ID
#   ASC_ISSUER_ID     Issuer ID
#   ASC_KEY_PATH      .p8 秘密鍵のパス
#   BUNDLE_ID         対象アプリの bundle identifier
#   SCREENSHOT_PATHS  アップロードする PNG のパス。カンマ区切りで、並べた順が表示順になる

require "base64"
require "digest"
require "json"
require "net/http"
require "openssl"
require "uri"

API_BASE = "https://api.appstoreconnect.apple.com"

# 画像の実寸から App Store Connect の表示タイプを決める。
# 1 つのサイズが複数のタイプで受け付けられる場合は、新しい方を選んでいる。
DISPLAY_TYPES = {
  [1320, 2868] => "APP_IPHONE_69",
  [2868, 1320] => "APP_IPHONE_69",
  [1290, 2796] => "APP_IPHONE_67",
  [2796, 1290] => "APP_IPHONE_67",
  [1284, 2778] => "APP_IPHONE_67",
  [2778, 1284] => "APP_IPHONE_67",
  [1242, 2688] => "APP_IPHONE_65",
  [2688, 1242] => "APP_IPHONE_65",
  [1242, 2208] => "APP_IPHONE_55",
  [2208, 1242] => "APP_IPHONE_55",
  [2048, 2732] => "APP_IPAD_PRO_3GEN_129",
  [2732, 2048] => "APP_IPAD_PRO_3GEN_129",
  [2064, 2752] => "APP_IPAD_PRO_3GEN_129",
  [2752, 2064] => "APP_IPAD_PRO_3GEN_129"
}.freeze

# このいずれかの状態なら、バージョンのメタデータを編集できる。
EDITABLE_VERSION_STATES = %w[
  PREPARE_FOR_SUBMISSION
  DEVELOPER_REJECTED
  REJECTED
  METADATA_REJECTED
  INVALID_BINARY
].freeze

def base64url(data)
  Base64.urlsafe_encode64(data, padding: false)
end

# App Store Connect API 用の JWT (ES256) を組み立てる。
# 署名は DER で返るため、JWT が求める R||S の生バイト列に変換している。
def token
  @token ||= begin
    now = Time.now.to_i
    header = { alg: "ES256", kid: ENV.fetch("ASC_KEY_ID"), typ: "JWT" }
    payload = {
      iss: ENV.fetch("ASC_ISSUER_ID"),
      iat: now,
      exp: now + 20 * 60,
      aud: "appstoreconnect-v1"
    }

    signing_input = [header, payload].map { |part| base64url(JSON.generate(part)) }.join(".")
    key = OpenSSL::PKey::EC.new(File.read(ENV.fetch("ASC_KEY_PATH")))
    der = key.sign(OpenSSL::Digest.new("SHA256"), signing_input)
    signature = OpenSSL::ASN1.decode(der).value.map { |value| value.value.to_s(2).rjust(32, "\x00").b }.join

    "#{signing_input}.#{base64url(signature)}"
  end
end

def api(method, path, body = nil)
  uri = URI.parse(path.start_with?("http") ? path : "#{API_BASE}#{path}")
  request_class = {
    get: Net::HTTP::Get,
    post: Net::HTTP::Post,
    patch: Net::HTTP::Patch,
    delete: Net::HTTP::Delete
  }.fetch(method)

  request = request_class.new(uri)
  request["Authorization"] = "Bearer #{token}"
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(body) if body

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  unless response.is_a?(Net::HTTPSuccess)
    abort "App Store Connect API エラー: #{method.to_s.upcase} #{uri.path} -> #{response.code}\n#{response.body}"
  end

  response.body.to_s.empty? ? nil : JSON.parse(response.body)
end

def png_dimensions(path)
  header = File.binread(path, 24)
  unless header && header[0, 8] == "\x89PNG\r\n\x1A\n".b
    abort "PNG ではありません: #{path}"
  end

  header[16, 8].unpack("N2")
end

def version_state(version)
  attributes = version["attributes"] || {}
  attributes["appVersionState"] || attributes["appStoreState"]
end

# 予約で返ってきた upload operation に従ってファイルを分割送信する。
def upload(operations, path)
  File.open(path, "rb") do |file|
    operations.each do |operation|
      file.seek(operation["offset"])
      uri = URI.parse(operation["url"])
      request = Net::HTTP::Put.new(uri)
      (operation["requestHeaders"] || []).each { |header| request[header["name"]] = header["value"] }
      request.body = file.read(operation["length"])

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
      unless response.is_a?(Net::HTTPSuccess)
        abort "スクリーンショットの送信に失敗しました: #{response.code}\n#{response.body}"
      end
    end
  end
end

# アップロードの成功と Apple 側での受理は別物なので、処理が終わるまで見届ける。
def wait_until_processed(screenshot_id)
  30.times do
    delivery = api(:get, "/v1/appScreenshots/#{screenshot_id}").dig("data", "attributes", "assetDeliveryState")
    case delivery&.fetch("state", nil)
    when "COMPLETE"
      return
    when "FAILED"
      abort "スクリーンショットが Apple 側で拒否されました: #{JSON.generate(delivery['errors'])}"
    end

    sleep 5
  end

  abort "スクリーンショットの処理が終わりませんでした"
end

def screenshot_set_id(localization_id, display_type)
  sets = api(:get, "/v1/appStoreVersionLocalizations/#{localization_id}/appScreenshotSets?limit=50")
  existing = sets["data"].find { |set| set.dig("attributes", "screenshotDisplayType") == display_type }
  return existing["id"] if existing

  created = api(:post, "/v1/appScreenshotSets", {
    data: {
      type: "appScreenshotSets",
      attributes: { screenshotDisplayType: display_type },
      relationships: {
        appStoreVersionLocalization: {
          data: { type: "appStoreVersionLocalizations", id: localization_id }
        }
      }
    }
  })
  created.dig("data", "id")
end

def upload_screenshot(set_id, path)
  reservation = api(:post, "/v1/appScreenshots", {
    data: {
      type: "appScreenshots",
      attributes: { fileSize: File.size(path), fileName: File.basename(path) },
      relationships: {
        appScreenshotSet: { data: { type: "appScreenshotSets", id: set_id } }
      }
    }
  })

  screenshot_id = reservation.dig("data", "id")
  upload(reservation.dig("data", "attributes", "uploadOperations"), path)

  api(:patch, "/v1/appScreenshots/#{screenshot_id}", {
    data: {
      type: "appScreenshots",
      id: screenshot_id,
      attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.file(path).hexdigest }
    }
  })

  wait_until_processed(screenshot_id)
  screenshot_id
end

# セットの中身を、渡した順序どおりに置き換える。
def replace_screenshots(set_id, paths)
  api(:get, "/v1/appScreenshotSets/#{set_id}/appScreenshots?limit=50")["data"].each do |screenshot|
    api(:delete, "/v1/appScreenshots/#{screenshot['id']}")
  end

  ids = paths.map { |path| upload_screenshot(set_id, path) }

  # アップロードした順が表示順になる保証はないため、明示的に並べ替える
  api(:patch, "/v1/appScreenshotSets/#{set_id}/relationships/appScreenshots", {
    data: ids.map { |id| { type: "appScreenshots", id: id } }
  })
end

bundle_id = ENV.fetch("BUNDLE_ID")
paths = ENV.fetch("SCREENSHOT_PATHS").split(",").map(&:strip).reject(&:empty?)
abort "SCREENSHOT_PATHS が空です" if paths.empty?

# 同じ表示タイプのものは 1 つのセットにまとめる。
# Hash は挿入順を保つため、SCREENSHOT_PATHS に並べた順がそのまま表示順になる。
groups = paths.group_by do |screenshot|
  width, height = png_dimensions(screenshot)
  display_type = DISPLAY_TYPES.fetch([width, height]) do
    abort "#{width}x#{height} に対応する App Store Connect の表示タイプがありません (#{screenshot})"
  end
  puts "スクリーンショット: #{File.basename(screenshot)} #{width}x#{height} (#{display_type})"
  display_type
end

apps = api(:get, "/v1/apps?filter[bundleId]=#{URI.encode_www_form_component(bundle_id)}&limit=1")
app_id = apps["data"].first&.fetch("id") or abort "#{bundle_id} のアプリが見つかりません"

versions = api(:get, "/v1/apps/#{app_id}/appStoreVersions?limit=10")
version = versions["data"].find { |candidate| EDITABLE_VERSION_STATES.include?(version_state(candidate)) }
unless version
  states = versions["data"].map { |candidate| "#{candidate.dig('attributes', 'versionString')} (#{version_state(candidate)})" }
  abort "編集可能なバージョンがありません。App Store Connect で提出準備中のバージョンを用意してください。\n現在のバージョン: #{states.join(', ')}"
end
puts "対象バージョン: #{version.dig('attributes', 'versionString')} (#{version_state(version)})"

localizations = api(:get, "/v1/appStoreVersions/#{version['id']}/appStoreVersionLocalizations?limit=50")["data"]
abort "ロケールが 1 つもありません" if localizations.empty?

localizations.each do |localization|
  locale = localization.dig("attributes", "locale")
  groups.each do |display_type, group_paths|
    set_id = screenshot_set_id(localization["id"], display_type)
    replace_screenshots(set_id, group_paths)
    puts "アップロード完了: #{locale} / #{display_type} (#{group_paths.size} 枚)"
  end
end
