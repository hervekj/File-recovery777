#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PROJECT_NAME="Reloaz"
VERSION="1.0.0"

OUTPUT_ROOT="$(pwd)/reloaz-recovery-$(date +%Y%m%d-%H%M%S)"
RECOVER_TYPE="all"
MODE="auto"
SOURCE=""

function usage() {
  cat <<EOF
$PROJECT_NAME - Recover lost or formatted files, videos, and audio from a memory card

Usage:
  $0 -s <source> [-o <output-dir>] [-t <type>] [-m <mode>] [-h]

Options:
  -s <source>      Path to the memory card device, disk image, or mounted folder
  -o <output-dir>  Destination folder for recovered files (default: $OUTPUT_ROOT)
  -t <type>        Recovery type: all, video, audio, photo, docs
  -m <mode>        Recovery mode: auto, quick, deep
  -h               Show this help message

Modes:
  auto  - Choose quick recovery for mounted folders, deep recovery for raw devices/images
  quick - Copy known file extensions from an accessible folder or mountpoint
  deep  - Use PhotoRec to carve recoverable files from a raw device/image

Types:
  all   - Recover videos, audio, photos, documents, and archives
  video - Recover only common video formats
  audio - Recover only common audio formats
  photo - Recover only photo/image formats
  docs  - Recover documents and archives

Examples:
  $0 -s /media/user/CARD -t video
  $0 -s /dev/sdb -o /tmp/recovery -m deep
  $0 -s card.img -t all -m auto
EOF
}

function log() {
  echo "[$PROJECT_NAME] $*"
}

function error() {
  echo "[$PROJECT_NAME] ERROR: $*" >&2
  exit 1
}

function require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "Command '$cmd' not found. Install it first and rerun the script."
  fi
}

function is_raw_source() {
  local src="$1"
  if [ -b "$src" ] || [ -f "$src" ] && file "$src" | grep -qiE 'disk image|raw image|filesystem data|DOS/MBR boot sector'; then
    return 0
  fi
  return 1
}

function build_extension_pattern() {
  case "$RECOVER_TYPE" in
    video)
      echo 'mp4 mov avi mkv m4v mpg m2ts ts flv webm wmv'
      ;;
    audio)
      echo 'mp3 wav aac m4a flac ogg wma'
      ;;
    photo)
      echo 'jpg jpeg png gif heic bmp tif tiff cr2 nef arw dng'
      ;;
    docs)
      echo 'pdf doc docx xls xlsx ppt pptx txt rtf odt zip rar tar gz 7z'
      ;;
    all|*)
      echo 'mp4 mov avi mkv m4v mpg m2ts ts flv webm wmv mp3 wav aac m4a flac ogg wma jpg jpeg png gif heic bmp tif tiff cr2 nef arw dng pdf doc docx xls xlsx ppt pptx txt rtf odt zip rar tar gz 7z'
      ;;
  esac
}

function create_output_dir() {
  mkdir -p "$OUTPUT_ROOT"
  log "Recovery destination: $OUTPUT_ROOT"
}

function quick_recovery() {
  local src="$1"
  local extensions
  extensions=$(build_extension_pattern)

  log "Running quick recovery from mounted source: $src"
  log "Scanning for: $extensions"

  local count=0
  while IFS= read -r ext; do
    find "$src" -type f \( -iname "*.$ext" \) -print0 2>/dev/null | while IFS= read -r -d '' file; do
      local rel
      rel="$(realpath --relative-to="$src" "$file" 2>/dev/null || echo "$(basename "$file")")"
      local target="$OUTPUT_ROOT/$rel"
      mkdir -p "$(dirname "$target")"
      cp -n "$file" "$target" && ((count++))
    done
  done <<<"$extensions"

  if [ "$count" -gt 0 ]; then
    log "Copied $count recovered files to $OUTPUT_ROOT"
  else
    log "No matching files found in mounted source. Try deep mode with PhotoRec for formatted cards or raw images."
  fi
}

function deep_recovery() {
  local src="$1"
  local output_dir="$OUTPUT_ROOT"

  require_command photorec

  log "Running deep recovery using PhotoRec"
  log "Source: $src"
  log "Output: $output_dir"

  if [ ! -e "$src" ]; then
    error "Source path does not exist: $src"
  fi

  printf "\n*** PhotoRec recovery starting. Follow the on-screen menu to confirm the device and filesystem options. ***\n\n"
  photorec /d "$output_dir" /cmd "$src" options,search
}

function run_recovery() {
  local src="$1"
  if [ "$MODE" = "quick" ]; then
    quick_recovery "$src"
    return
  fi

  if [ "$MODE" = "deep" ]; then
    deep_recovery "$src"
    return
  fi

  if [ -d "$src" ]; then
    quick_recovery "$src"
    return
  fi

  if is_raw_source "$src" || [ -b "$src" ]; then
    log "Detected raw device/image source; switching to deep recovery mode."
    deep_recovery "$src"
    return
  fi

  if [ -f "$src" ]; then
    log "Source is a file. Trying quick recovery if the file is a mounted image or fallback to deep recovery."
    quick_recovery "$src" || deep_recovery "$src"
    return
  fi

  error "Unable to determine recovery mode for source: $src"
}

while getopts ":s:o:t:m:h" opt; do
  case $opt in
    s) SOURCE="$OPTARG" ;;
    o) OUTPUT_ROOT="$OPTARG" ;;
    t) RECOVER_TYPE="$OPTARG" ;;
    m) MODE="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) error "Option -$OPTARG requires an argument." ;;
    \?) error "Invalid option: -$OPTARG" ;;
  esac
done

if [ -z "$SOURCE" ]; then
  usage
  error "A source path is required. Use -s <source>."
fi

create_output_dir
run_recovery "$SOURCE"
