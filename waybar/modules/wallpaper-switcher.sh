#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/wallpaper-switcher.json"

log() {
  printf '[wallpaper-switcher] %s\n' "$*" >&2
}

notify() {
  local body="${1}"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Waybar" "Wallpaper Switcher" "${body}" >/dev/null 2>&1 || true
  fi
}

config_get() {
  local expr="${1}"
  jq -r "${expr}" "${CONFIG_FILE}"
}

expand_path() {
  local path="${1}"
  case "${path}" in
    "~")
      printf '%s\n' "${HOME}"
      ;;
    "~/"*)
      printf '%s/%s\n' "${HOME}" "${path#"~/"}"
      ;;
    *)
      printf '%s\n' "${path}"
      ;;
  esac
}

join_path() {
  local base="${1}"
  local part="${2}"
  if [[ "${base}" == "/" ]]; then
    printf '/%s\n' "${part}"
    return
  fi
  printf '%s/%s\n' "${base}" "${part}"
}

resolve_directory_case_insensitive() {
  local requested_path="${1}"
  local normalized_path
  local current
  local segment
  local next_path
  local matched_segment

  normalized_path="$(expand_path "${requested_path}")"
  if [[ -d "${normalized_path}" ]]; then
    printf '%s\n' "${normalized_path}"
    return
  fi

  if [[ "${normalized_path}" == /* ]]; then
    current="/"
    normalized_path="${normalized_path#/}"
  else
    current="."
  fi

  IFS='/' read -r -a path_segments <<< "${normalized_path}"
  for segment in "${path_segments[@]}"; do
    [[ -n "${segment}" ]] || continue

    next_path="$(join_path "${current}" "${segment}")"
    if [[ -d "${next_path}" ]]; then
      current="${next_path}"
      continue
    fi

    matched_segment=""
    if [[ -d "${current}" ]]; then
      while IFS= read -r candidate_name; do
        if [[ "${candidate_name,,}" == "${segment,,}" ]]; then
          matched_segment="${candidate_name}"
          break
        fi
      done < <(find "${current}" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
    fi

    if [[ -n "${matched_segment}" ]]; then
      current="$(join_path "${current}" "${matched_segment}")"
    else
      current="${next_path}"
    fi
  done

  printf '%s\n' "${current}"
}

STATE_FILE="$(expand_path "$(config_get '.state_file // "~/.config/waybar/wallpaper-switcher.state.json"')")"
CACHE_DIR="$(expand_path "$(config_get '.cache_dir // "~/.cache/niri-wallpaper-switcher"')")"
WALLPAPER_DIR="$(resolve_directory_case_insensitive "~/Pictures/Wallpaper")"
VIDEO_DIR="$(resolve_directory_case_insensitive "~/Videos/WallVideo")"
WAYBAR_SIGNAL="$(config_get '.signal // 9')"

ensure_directories() {
  mkdir -p "$(dirname "${STATE_FILE}")"
  mkdir -p "${CACHE_DIR}"
  mkdir -p "${WALLPAPER_DIR}"
  mkdir -p "${VIDEO_DIR}"
}

signal_waybar() {
  pkill -RTMIN+"${WAYBAR_SIGNAL}" waybar >/dev/null 2>&1 || true
}

is_image() {
  local path="${1,,}"
  case "${path}" in
    *.jpg|*.jpeg|*.png|*.webp|*.bmp|*.gif|*.avif)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_video() {
  local path="${1,,}"
  case "${path}" in
    *.mp4|*.mkv|*.webm|*.mov|*.avi|*.m4v)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

asset_kind() {
  local path="${1}"
  if is_image "${path}"; then
    printf 'image\n'
    return
  fi
  if is_video "${path}"; then
    printf 'video\n'
    return
  fi
  return 1
}

asset_display() {
  local path="${1}"
  local kind="${2}"
  local label
  label="$(basename "${path}")"
  case "${kind}" in
    image)
      printf '图片  %s\n' "${label}"
      ;;
    video)
      printf '视频  %s\n' "${label}"
      ;;
    *)
      printf '%s\n' "${label}"
      ;;
  esac
}

wallpaper_images() {
  ensure_directories
  find "${WALLPAPER_DIR}" -maxdepth 1 -type f | sort | while IFS= read -r path; do
    if is_image "${path}"; then
      printf '%s\t%s\n' "${path}" "$(asset_display "${path}" image)"
    fi
  done
}

wallpaper_videos() {
  ensure_directories
  find "${VIDEO_DIR}" -maxdepth 1 -type f | sort | while IFS= read -r path; do
    if is_video "${path}"; then
      printf '%s\t%s\n' "${path}" "$(asset_display "${path}" video)"
    fi
  done
}

combined_assets() {
  {
    wallpaper_images
    wallpaper_videos
  } | sed '/^$/d'
}

first_asset_path() {
  combined_assets | sed -n '1s/\t.*//p'
}

menu_select() {
  local prompt="${1}"
  local lines
  local width

  lines="$(config_get '.menu.lines // 14')"
  width="$(config_get '.menu.width // 54')"

  fuzzel --dmenu \
    --prompt "${prompt}" \
    --lines "${lines}" \
    --width "${width}" \
    --with-nth 2 \
    --accept-nth 1 \
    --match-nth 2 \
    --only-match
}

choose_wallpaper_asset() {
  local prompt="${1}"
  local choice

  choice="$(
    {
      printf 'transparent\t透明  Wallpaper\n'
      combined_assets
    } | menu_select "${prompt}"
  )" || exit 0

  printf '%s\n' "${choice}"
}

choose_regular_asset() {
  local prompt="${1}"
  local choice

  choice="$(combined_assets | menu_select "${prompt}")" || exit 0
  printf '%s\n' "${choice}"
}

state_json() {
  if [[ -f "${STATE_FILE}" ]]; then
    cat "${STATE_FILE}"
  fi
}

state_valid() {
  local state="${1}"
  local mode
  local wallpaper_type
  local wallpaper_path
  local backdrop_type
  local backdrop_path

  mode="$(jq -r '.mode // "empty"' <<<"${state}")"
  wallpaper_type="$(jq -r '.wallpaper.type // "transparent"' <<<"${state}")"
  wallpaper_path="$(jq -r '.wallpaper.path // ""' <<<"${state}")"
  backdrop_type="$(jq -r '.backdrop.type // empty' <<<"${state}")"
  backdrop_path="$(jq -r '.backdrop.path // ""' <<<"${state}")"

  case "${wallpaper_type}" in
    transparent)
      ;;
    image|video)
      [[ -n "${wallpaper_path}" && -f "${wallpaper_path}" ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac

  if [[ "${mode}" == "split" ]]; then
    case "${backdrop_type}" in
      image|video)
        [[ -n "${backdrop_path}" && -f "${backdrop_path}" ]] || return 1
        ;;
      *)
        return 1
        ;;
    esac
  fi

  return 0
}

default_state_json() {
  local first_path

  first_path="$(first_asset_path || true)"
  if [[ -z "${first_path}" ]]; then
    jq -cn '{
      mode: "empty",
      wallpaper: { type: "transparent", path: "" },
      backdrop: { type: "image", path: "" }
    }'
    return
  fi

  build_auto_state_json "${first_path}"
}

resolved_state_json() {
  local state
  local mode
  local wallpaper_path

  state="$(state_json || true)"
  if [[ -n "${state}" ]] && jq empty <<<"${state}" >/dev/null 2>&1 && state_valid "${state}"; then
    mode="$(jq -r '.mode // "empty"' <<<"${state}")"
    if [[ "${mode}" == "auto" ]]; then
      wallpaper_path="$(jq -r '.wallpaper.path' <<<"${state}")"
      build_auto_state_json "${wallpaper_path}"
      return
    fi
    printf '%s\n' "${state}"
    return
  fi

  default_state_json
}

write_state_json() {
  local state="${1}"
  ensure_directories
  jq '.' <<<"${state}" > "${STATE_FILE}"
}

hash_key() {
  local path="${1}"
  local kind="${2}"
  local stamp

  stamp="$(stat -c '%Y-%s' "${path}")"
  printf '%s\n' "${path}|${kind}|${stamp}" | sha256sum | cut -d' ' -f1
}

generate_auto_backdrop() {
  local source_path="${1}"
  local kind="${2}"
  local key
  local frame_path
  local output_path
  local blur_source

  key="$(hash_key "${source_path}" "${kind}")"
  frame_path="${CACHE_DIR}/frame-${key}.png"
  output_path="${CACHE_DIR}/auto-backdrop-${key}.png"

  if [[ -f "${output_path}" ]]; then
    printf '%s\n' "${output_path}"
    return
  fi

  if [[ "${kind}" == "video" ]]; then
    ffmpeg -y -loglevel error -i "${source_path}" -frames:v 1 "${frame_path}"
    blur_source="${frame_path}"
  else
    blur_source="${source_path}"
  fi

  magick "${blur_source}" \
    -strip \
    -filter Lanczos \
    -resize 25% \
    -blur 0x10 \
    -resize 400% \
    "${output_path}"

  printf '%s\n' "${output_path}"
}

build_auto_state_json() {
  local wallpaper_path="${1}"
  local wallpaper_type
  local backdrop_path

  wallpaper_type="$(asset_kind "${wallpaper_path}")"
  backdrop_path="$(generate_auto_backdrop "${wallpaper_path}" "${wallpaper_type}")"

  jq -cn \
    --arg wallpaper_path "${wallpaper_path}" \
    --arg wallpaper_type "${wallpaper_type}" \
    --arg backdrop_path "${backdrop_path}" '
    {
      mode: "auto",
      wallpaper: {
        type: $wallpaper_type,
        path: $wallpaper_path
      },
      backdrop: {
        type: "image",
        path: $backdrop_path,
        generated: true,
        source: $wallpaper_path
      }
    }'
}

build_split_state_json() {
  local wallpaper_choice="${1}"
  local backdrop_choice="${2}"
  local wallpaper_type
  local wallpaper_path
  local backdrop_type

  if [[ "${wallpaper_choice}" == "transparent" ]]; then
    wallpaper_type="transparent"
    wallpaper_path=""
  else
    wallpaper_type="$(asset_kind "${wallpaper_choice}")"
    wallpaper_path="${wallpaper_choice}"
  fi

  backdrop_type="$(asset_kind "${backdrop_choice}")"

  jq -cn \
    --arg wallpaper_type "${wallpaper_type}" \
    --arg wallpaper_path "${wallpaper_path}" \
    --arg backdrop_type "${backdrop_type}" \
    --arg backdrop_path "${backdrop_choice}" '
    {
      mode: "split",
      wallpaper: {
        type: $wallpaper_type,
        path: $wallpaper_path
      },
      backdrop: {
        type: $backdrop_type,
        path: $backdrop_path,
        generated: false
      }
    }'
}

stop_wallpaper_and_backdrop() {
  pkill -x mpvpaper >/dev/null 2>&1 || true
  pkill -x swaybg >/dev/null 2>&1 || true
  pkill -x swww-daemon >/dev/null 2>&1 || true
}

ensure_swww_daemon() {
  local i

  if ! pgrep -x swww-daemon >/dev/null 2>&1; then
    nohup swww-daemon >/dev/null 2>&1 &
  fi

  for ((i = 0; i < 30; i += 1)); do
    if swww query >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done

  return 1
}

start_backdrop() {
  local state="${1}"
  local backdrop_type
  local backdrop_path

  backdrop_type="$(jq -r '.backdrop.type' <<<"${state}")"
  backdrop_path="$(jq -r '.backdrop.path' <<<"${state}")"

  case "${backdrop_type}" in
    image)
      [[ -n "${backdrop_path}" ]] || return 0
      ensure_swww_daemon
      swww img "${backdrop_path}" --resize crop --filter Lanczos3 --transition-type none >/dev/null 2>&1
      ;;
    video)
      mpvpaper --fork --layer background -o "no-audio loop-file=inf" ALL "${backdrop_path}" >/dev/null 2>&1
      ;;
    *)
      log "unsupported backdrop type: ${backdrop_type}"
      return 1
      ;;
  esac
}

start_wallpaper() {
  local state="${1}"
  local wallpaper_type
  local wallpaper_path

  wallpaper_type="$(jq -r '.wallpaper.type' <<<"${state}")"
  wallpaper_path="$(jq -r '.wallpaper.path // ""' <<<"${state}")"

  case "${wallpaper_type}" in
    transparent)
      return 0
      ;;
    image)
      nohup swaybg -i "${wallpaper_path}" -m fill >/dev/null 2>&1 &
      ;;
    video)
      mpvpaper --fork --layer bottom -o "no-audio loop-file=inf" ALL "${wallpaper_path}" >/dev/null 2>&1
      ;;
    *)
      log "unsupported wallpaper type: ${wallpaper_type}"
      return 1
      ;;
  esac
}

apply_state_json() {
  local state="${1}"

  stop_wallpaper_and_backdrop
  start_backdrop "${state}"
  start_wallpaper "${state}"
  write_state_json "${state}"
  signal_waybar
}

mode_label() {
  local mode="${1}"
  case "${mode}" in
    auto)
      printf 'Auto\n'
      ;;
    split)
      printf 'Split\n'
      ;;
    *)
      printf 'Empty\n'
      ;;
  esac
}

asset_label_from_state() {
  local type="${1}"
  local path="${2}"
  local generated="${3:-false}"

  case "${type}" in
    transparent)
      printf '透明\n'
      ;;
    image|video)
      if [[ "${generated}" == "true" ]]; then
        printf '自动模糊  %s\n' "$(basename "${path}")"
      else
        printf '%s\n' "$(basename "${path}")"
      fi
      ;;
    *)
      printf '未设置\n'
      ;;
  esac
}

status_json() {
  local state
  local mode
  local wallpaper_type
  local wallpaper_path
  local backdrop_type
  local backdrop_path
  local backdrop_generated
  local text
  local tooltip

  state="$(resolved_state_json)"
  mode="$(jq -r '.mode' <<<"${state}")"

  if [[ "${mode}" == "empty" ]]; then
    jq -cn \
      --arg text "󰸉 Empty" \
      --arg tooltip "未找到可用的壁纸资源\n\n图片目录: ${WALLPAPER_DIR}\n视频目录: ${VIDEO_DIR}\n\n左键: 打开壁纸菜单" \
      '{"text": $text, "tooltip": $tooltip, "class": ["wallpaper-switcher", "mode-empty"], "alt": "empty"}'
    return
  fi

  wallpaper_type="$(jq -r '.wallpaper.type' <<<"${state}")"
  wallpaper_path="$(jq -r '.wallpaper.path // ""' <<<"${state}")"
  backdrop_type="$(jq -r '.backdrop.type' <<<"${state}")"
  backdrop_path="$(jq -r '.backdrop.path // ""' <<<"${state}")"
  backdrop_generated="$(jq -r '.backdrop.generated // false' <<<"${state}")"

  text="󰸉 $(mode_label "${mode}")"
  tooltip="$(printf '模式: %s\nWallpaper: %s\nBackdrop: %s\n\n左键: 打开壁纸菜单' \
    "$(mode_label "${mode}")" \
    "$(asset_label_from_state "${wallpaper_type}" "${wallpaper_path}")" \
    "$(asset_label_from_state "${backdrop_type}" "${backdrop_path}" "${backdrop_generated}")")"

  jq -cn \
    --arg text "${text}" \
    --arg tooltip "${tooltip}" \
    --arg mode_class "mode-${mode}" \
    --arg alt "${mode}" \
    '{"text": $text, "tooltip": $tooltip, "class": ["wallpaper-switcher", $mode_class], "alt": $alt}'
}

auto_mode_flow() {
  local wallpaper_choice
  local state

  if [[ -z "$(combined_assets)" ]]; then
    notify "没有找到可用的图片或视频资源"
    exit 0
  fi

  wallpaper_choice="$(choose_regular_asset "Auto Blur> ")"
  [[ -n "${wallpaper_choice}" ]] || exit 0

  state="$(build_auto_state_json "${wallpaper_choice}")"
  apply_state_json "${state}"
  notify "已切换到自动高斯模糊模式"
}

split_mode_flow() {
  local wallpaper_choice
  local backdrop_choice
  local state

  if [[ -z "$(combined_assets)" ]]; then
    notify "没有找到可用的图片或视频资源"
    exit 0
  fi

  wallpaper_choice="$(choose_wallpaper_asset "Wallpaper> ")"
  [[ -n "${wallpaper_choice}" ]] || exit 0

  backdrop_choice="$(choose_regular_asset "Backdrop> ")"
  [[ -n "${backdrop_choice}" ]] || exit 0

  state="$(build_split_state_json "${wallpaper_choice}" "${backdrop_choice}")"
  apply_state_json "${state}"
  notify "已切换到分选模式"
}

show_menu() {
  local action
  local state
  local current_mode

  state="$(resolved_state_json)"
  current_mode="$(jq -r '.mode' <<<"${state}")"

  action="$(
    printf 'auto\t自动高斯模糊模式  [%s]\nsplit\t分选模式\nreapply\t重新应用当前配置\n' "$(mode_label "${current_mode}")" |
      menu_select "Wallpaper> "
  )" || exit 0

  case "${action}" in
    auto)
      auto_mode_flow
      ;;
    split)
      split_mode_flow
      ;;
    reapply)
      apply_state_json "${state}"
      notify "已重新应用当前配置"
      ;;
    *)
      exit 0
      ;;
  esac
}

restore_state() {
  local state

  state="$(resolved_state_json)"
  if [[ "$(jq -r '.mode' <<<"${state}")" == "empty" ]]; then
    stop_wallpaper_and_backdrop
    signal_waybar
    return
  fi

  apply_state_json "${state}"
}

usage() {
  cat <<'EOF'
Usage:
  wallpaper-switcher.sh status
  wallpaper-switcher.sh menu
  wallpaper-switcher.sh restore
EOF
}

main() {
  local command="${1:-status}"

  ensure_directories

  case "${command}" in
    status)
      status_json
      ;;
    menu)
      show_menu
      ;;
    restore)
      restore_state
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
