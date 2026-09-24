#!/bin/sh
export PATH="${PATH:+$PATH:}/usr/sbin:/usr/bin:/sbin:/bin"

# Shared helpers for the CLI and authenticated LuCI renderer.

# Keep generated filenames and RPC tokens in a strict ASCII subset.
safe_ssid() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/_/g'
}

# Match the boolean values accepted by OpenWrt's config_get_bool helper.
wifi_qr_is_true() {
  local value

  value="$(printf '%s' "$1" | tr 'A-Z' 'a-z' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  case "$value" in
    1|on|true|yes|enabled)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# UCI may store the LAN address with a CIDR suffix, which is not part of a URL
# host.
wifi_qr_http_base_url() {
  local lan_ip="${1%%/*}"

  [ -n "$lan_ip" ] || return 0

  printf 'http://%s' "$lan_ip"
}

wifi_qr_auth_type() {
  local enc

  enc="$(printf '%s' "$1" | tr 'A-Z' 'a-z' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  case "$enc" in
    *wep*)
      printf '%s\n' "WEP"
      ;;
    none|open|owe*|"")
      printf '%s\n' "nopass"
      ;;
    *psk*|sae|sae-*|sae+*)
      printf '%s\n' "WPA"
      ;;
    *)
      return 1
      ;;
  esac
}

# WPA3 transition-disable values follow the Wi-Fi QR extension used by LuCI.
wifi_qr_transition_disable() {
  local enc

  enc="$(printf '%s' "$1" | tr 'A-Z' 'a-z' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  case "$enc" in
    sae|sae+*)
      printf '%s' "0"
      ;;
    owe*)
      printf '%s' "3"
      ;;
  esac
}

# Resolve the selected WEP slot to its actual key and strip UCI's s: marker.
wifi_qr_key_for_iface() {
  local iface_index="$1"
  local enc="$2"
  local key

  key="$(uci -q get "wireless.@wifi-iface[$iface_index].key" || :)"

  case "$(printf '%s' "$enc" | tr 'A-Z' 'a-z')" in
    *wep*)
      case "$key" in
        1|2|3|4)
          key="$(uci -q get "wireless.@wifi-iface[$iface_index].key$key" || :)"
          ;;
      esac

      case "$key" in
        s:*) key="${key#s:}" ;;
      esac
      ;;
  esac

  printf '%s' "$key"
}

# Parse idN_BANDTAG_SSID_SAFE.svg into WIFI_QR_TOKEN_* globals.
wifi_qr_parse_token() {
  local spec="$1"
  local basename id_part rest band_tag ssid_safe id_num

  basename="${spec##*/}"
  basename="${basename%.svg}"

  case "$basename" in
    id[0-9]*_*)
      ;;
    *)
      return 1
      ;;
  esac

  id_part="${basename%%_*}" # idN.
  rest="${basename#*_}"

  case "$rest" in
    *_*)
      band_tag="${rest%%_*}"
      ssid_safe="${rest#*_}"
      ;;
    *)
      return 1
      ;;
  esac

  id_num="${id_part#id}"
  case "$id_num" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac

  WIFI_QR_TOKEN_ID="$id_num"
  WIFI_QR_TOKEN_BAND_TAG="$band_tag"
  WIFI_QR_TOKEN_SSID_SAFE="$ssid_safe"
  WIFI_QR_TOKEN_BASENAME="$basename"

  return 0
}

# Prefer the modern band option and fall back to legacy hwmode configurations.
wifi_band_for_device() {
  local dev="$1"

  [ -n "$dev" ] || return 0

  local band hwmode

  band="$(uci -q get wireless."$dev".band || :)"
  band="$(printf '%s' "$band" | tr 'A-Z' 'a-z')"

  case "$band" in
    2g*)
      printf '%s\n' "2.4GHz"
      return 0
      ;;
    5g*)
      printf '%s\n' "5GHz"
      return 0
      ;;
    6g*)
      printf '%s\n' "6GHz"
      return 0
      ;;
  esac

  hwmode="$(uci -q get wireless."$dev".hwmode || :)"
  hwmode="$(printf '%s' "$hwmode" | tr 'A-Z' 'a-z')"

  case "$hwmode" in
    *g*|*b*)
      printf '%s\n' "2.4GHz"
      ;;
    *a*|*ac*)
      printf '%s\n' "5GHz"
      ;;
    *)
      ;;
  esac
}

wifi_qr_payload() {
  local ssid="$1"
  local key="$2"
  local enc="$3"
  local hidden="${4:-0}"

  local t transition_disable
  t="$(wifi_qr_auth_type "$enc")" || return 1
  transition_disable="$(wifi_qr_transition_disable "$enc")"

  local ssid_esc key_esc
  ssid_esc="$(escape_wifi "$ssid")"

  printf 'WIFI:T:%s;' "$t"
  [ -z "$transition_disable" ] || printf 'R:%s;' "$transition_disable"
  printf 'S:%s;' "$ssid_esc"
  if wifi_qr_is_true "$hidden"; then
    printf 'H:true;'
  fi

  if [ "$t" != "nopass" ]; then
    key_esc="$(escape_wifi "$key")"
    printf 'P:%s;' "$key_esc"
  fi

  printf ';'
}

# POSIX sh has no associative arrays. Values are escaped before assignment to
# the internal dynamic variables used below.
get_var() {
  eval "printf '%s' \"\${$1-}\""
}

set_var() {
  local name="$1"
  local value="$2"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\\$}"
  value="${value//\`/\\\`}"

  eval "$name=\"$value\""
}

add_band() {
  local current="$1"
  local band="$2"

  [ -n "$band" ] || {
    printf '%s\n' "$current"
    return 0
  }

  if [ -z "$current" ]; then
    printf '%s\n' "$band"
    return 0
  fi

  local w
  for w in $current; do
    [ "$w" = "$band" ] && {
      printf '%s\n' "$current"
      return 0
    }
  done

  printf '%s %s\n' "$current" "$band"
}

_wifi_qr_band_flags() {
  local bands_list="$1"
  local have24=0 have5=0 have6=0 w

  for w in $bands_list; do
    case "$w" in
      2.4GHz) have24=1 ;;
      5GHz)   have5=1 ;;
      6GHz)   have6=1 ;;
    esac
  done

  printf '%s %s %s\n' "$have24" "$have5" "$have6"
}

_wifi_qr_build_band_core() {
  local have24="$1"
  local have5="$2"
  local have6="$3"
  local sep="$4"

  local core=""
  [ "$have24" -eq 1 ] && core="${core:+$core$sep}2.4"
  [ "$have5"  -eq 1 ] && core="${core:+$core$sep}5"
  [ "$have6"  -eq 1 ] && core="${core:+$core$sep}6"

  printf '%s' "$core"
}

build_band_label() {
  local bands_list="$1"

  [ -n "$bands_list" ] || return 0

  local have24 have5 have6 core
  local old_ifs="$IFS"

  IFS=' '
  read -r have24 have5 have6 <<EOF
$(_wifi_qr_band_flags "$bands_list")
EOF
  IFS="$old_ifs"

  core="$(_wifi_qr_build_band_core "$have24" "$have5" "$have6" "/")"
  [ -n "$core" ] || return 0

  printf '%sGHz' "$core"
}

build_band_tag() {
  local bands_list="$1"

  [ -n "$bands_list" ] || return 0

  local have24 have5 have6 core
  local old_ifs="$IFS"

  IFS=' '
  read -r have24 have5 have6 <<EOF
$(_wifi_qr_band_flags "$bands_list")
EOF
  IFS="$old_ifs"

  core="$(_wifi_qr_build_band_core "$have24" "$have5" "$have6" "-")"

  [ -n "$core" ] || return 0

  printf '%sGHz' "$core"
}

# Return the one canonical token accepted by the renderer for a payload group.
wifi_qr_group_token() {
  local group_id="$1"
  local ssid rep_idx bands band_tag

  case "$group_id" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac

  ssid="$(get_var "group_ssid_$group_id")"
  rep_idx="$(get_var "group_rep_idx_$group_id")"
  bands="$(get_var "group_bands_$group_id")"

  [ -n "$ssid" ] && [ -n "$rep_idx" ] || return 1

  band_tag="$(build_band_tag "$bands")"
  printf 'id%s_%s_%s.svg' "$rep_idx" "$band_tag" "$(safe_ssid "$ssid")"
}

band_label_from_tag() {
  local band_tag="$1"

  [ -n "$band_tag" ] || return 0

  local band_core="${band_tag%GHz}"
  local have24=0 have5=0 have6=0 part
  local old_ifs="$IFS"

  IFS='-'
  for part in $band_core; do
    case "$part" in
      2.4) have24=1 ;;
      5)   have5=1  ;;
      6)   have6=1  ;;
      *)   ;;
    esac
  done
  IFS="$old_ifs"

  if [ "$have24" -eq 0 ] && [ "$have5" -eq 0 ] && [ "$have6" -eq 0 ]; then
    return 0
  fi

  local core
  core="$(_wifi_qr_build_band_core "$have24" "$have5" "$have6" "/")"
  [ -n "$core" ] || return 0

  printf '%sGHz' "$core"
}

# Group enabled interfaces by complete QR payload. The first interface in UCI
# order is the canonical representative for every identical payload.
wifi_qr_build_groups() {
  local i ssid disabled dev dev_disabled key enc hidden auth_type
  local payload band g found_group gp gbands

  group_count=0

  i=0
  while :; do
    if ! uci -q show "wireless.@wifi-iface[$i]" >/dev/null 2>&1; then
      break
    fi

    ssid="$(uci -q get "wireless.@wifi-iface[$i].ssid" || :)"

    disabled="$(uci -q get "wireless.@wifi-iface[$i].disabled" || :)"
    dev="$(uci -q get "wireless.@wifi-iface[$i].device" || :)"

    dev_disabled=""
    if [ -n "$dev" ]; then
      dev_disabled="$(uci -q get "wireless.$dev.disabled" || :)"
    fi

    enc="$(uci -q get "wireless.@wifi-iface[$i].encryption" || :)"
    hidden="$(uci -q get "wireless.@wifi-iface[$i].hidden" || :)"

    if [ -n "$ssid" ] &&
       ! wifi_qr_is_true "$disabled" &&
       ! wifi_qr_is_true "$dev_disabled"; then
      if ! auth_type="$(wifi_qr_auth_type "$enc")"; then
        i=$((i+1))
        continue
      fi

      key="$(wifi_qr_key_for_iface "$i" "$enc")"
      if [ "$auth_type" != "nopass" ] && [ -z "$key" ]; then
        i=$((i+1))
        continue
      fi

      if wifi_qr_is_true "$hidden"; then
        hidden=1
      else
        hidden=0
      fi

      payload="$(wifi_qr_payload "$ssid" "$key" "$enc" "$hidden")"
      band="$(wifi_band_for_device "$dev")"

      g=1
      found_group=""
      while [ "$g" -le "$group_count" ]; do
        gp="$(get_var "group_payload_$g")"
        if [ "$gp" = "$payload" ]; then
          found_group="$g"
          break
        fi
        g=$((g+1))
      done

      if [ -n "$found_group" ]; then
        gbands="$(get_var "group_bands_$found_group")"
        gbands="$(add_band "$gbands" "$band")"
        set_var "group_bands_$found_group" "$gbands"
        set_var "iface_group_$i" "$found_group"
      else
        group_count=$((group_count+1))
        set_var "group_payload_$group_count" "$payload"
        set_var "group_ssid_$group_count" "$ssid"
        set_var "group_key_$group_count" "$key"
        set_var "group_enc_$group_count" "$enc"
        set_var "group_hidden_$group_count" "$hidden"
        set_var "group_rep_idx_$group_count" "$i"
        set_var "group_bands_$group_count" "$band"
        set_var "iface_group_$i" "$group_count"
      fi
    fi

    i=$((i+1))
  done
}

# Escape characters reserved by the Wi-Fi QR payload format.
escape_wifi() {
  local s="$1"

  s="${s//\\/\\\\}"
  s="${s//;/\\;}"
  s="${s//,/\\,}"
  s="${s//:/\\:}"
  s="${s//\"/\\\"}"

  printf '%s' "$s"
}

# Resize qrencode output and embed XML-escaped SSID and band labels.
fix_svg_size() {
  local size="$1"
  local label="$2"
  local band_label="$3"

  if command -v awk >/dev/null 2>&1; then
    # SVG transforms require a dot decimal separator regardless of locale.
    LC_NUMERIC=C awk -v size="$size" -v label="$label" -v band="$band_label" '
      function xml_escape(s, out, i, ch) {
        out = ""

        for (i = 1; i <= length(s); i++) {
          ch = substr(s, i, 1)

          if (ch == "&")
            out = out "&amp;"
          else if (ch == "<")
            out = out "&lt;"
          else if (ch == ">")
            out = out "&gt;"
          else if (ch == "\"")
            out = out "&quot;"
          else if (ch == sprintf("%c", 39))
            out = out "&apos;"
          else if (ch ~ /[[:cntrl:]]/ && ch != "\t" && ch != "\r" && ch != "\n")
            continue
          else
            out = out ch
        }

        return out
      }

      BEGIN {
        processed   = 0
        closed_g    = 0

        label = xml_escape(label)
        band  = xml_escape(band)

        if (length(band) > 0) {
          margin       = 4
          label_block  = 16
          band_block   = 14
          bottom_extra = 2
        }
        else {
          margin       = 8
          label_block  = 18
          band_block   = 0
          bottom_extra = 6
        }
      }

      /<svg/ && !processed {
        processed = 1
        line = $0

        orig = 0
        if (match(line, /viewBox="[^"]*"/)) {
          vb = substr(line, RSTART+9, RLENGTH-10)
          n  = split(vb, a, /[ ]+/)
          if (n >= 3)
            orig = a[3] + 0
        }

        if (orig <= 0) {
          if (match(line, /width="[0-9]+/)) {
            orig = substr(line, RSTART+7, RLENGTH-7) + 0
          }
        }

        if (orig <= 0)
          orig = size

        avail_w = size - 2*margin

        avail_h = size - 2*margin - label_block - band_block - bottom_extra
        if (avail_h <= 0)
          avail_h = size - 2*margin - bottom_extra

        scale_w = avail_w / orig
        scale_h = avail_h / orig
        if (scale_w < scale_h)
          scale = scale_w
        else
          scale = scale_h

        qr_w = orig * scale
        qr_h = orig * scale

        gsub(/width="[^"]*"/,  "width=\"" size "\"", line)
        gsub(/height="[^"]*"/, "height=\"" size "\"", line)

        if (line ~ /viewBox="/) {
          gsub(/viewBox="[^"]*"/,
               "viewBox=\"0 0 " size " " size "\"", line)
        }
        else {
          sub(/<svg/, "<svg viewBox=\"0 0 " size " " size "\"", line)
        }

        print line

        tx = margin
        ty = margin + label_block

        if (avail_w > qr_w)
          tx += (avail_w - qr_w) / 2

        printf "<g transform=\"translate(%0.3f,%0.3f) scale(%0.6f)\">\n", tx, ty, scale
        next
      }

      /<\/svg>/ && processed && !closed_g {
        print "</g>"
        closed_g = 1

        y = margin + 12
        printf "<text x=\"%d\" y=\"%d\" text-anchor=\"middle\" ",
               size / 2, y
        printf "font-size=\"14\" font-family=\"sans-serif\" font-weight=\"bold\">%s</text>\n",
               label

        if (length(band) > 0) {
          y2 = size - margin - bottom_extra
          printf "<text x=\"%d\" y=\"%d\" text-anchor=\"middle\" ",
                 size / 2, y2
          printf "font-size=\"12\" font-family=\"sans-serif\" font-weight=\"bold\">• %s</text>\n",
                 band
        }
        print $0
        next
      }

      { print }
    '
  else
    cat
  fi
}

gen_wifi_qr_svg() {
  local ssid="$1"
  local key="$2"
  local enc="$3"
  local band_label="$4"
  local hidden="${5:-0}"

  local size="${WIFI_QR_SIZE:-256}"

  local payload svg

  payload="$(wifi_qr_payload "$ssid" "$key" "$enc" "$hidden")" || return 1

  # Keep SSIDs and passwords out of qrencode's process arguments.
  svg="$(printf '%s' "$payload" | qrencode -m 0 -t SVG -o -)" || return 1

  printf '%s\n' "$svg" | fix_svg_size "$size" "$ssid" "$band_label"
}
