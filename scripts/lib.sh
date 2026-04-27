SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$(cd "$ROOT_DIR/configs" && pwd)"

REGISTRY="$CONFIG_DIR/registry.yaml"
CONTRIBUTORS="$CONFIG_DIR/contributors.yaml"
DIRS="$CONFIG_DIR/default_dirs.yaml"
ENV_FILE="$ROOT_DIR/.env"

validate_platform() {
  local platform="$1"
  case "$platform" in
    opencode|claudecode|pi) return 0 ;;
    *) echo "Error: unknown platform '$platform' (expected: opencode, claudecode, pi)" >&2; return 1 ;;
  esac
}

parse_registry_pattern() {
  local registry="$1"
  if [[ "$registry" != *":"* ]]; then
    echo "Error: '$registry' is not a valid registry pattern (expected type:name)" >&2
    return 1
  fi
  PARSED_TYPE="${registry%%:*}"
  PARSED_NAME="${registry#*:}"
  if ! sanitize_name "$PARSED_NAME"; then
    echo "Error: '$PARSED_NAME' is not a valid name (alphanumeric, dashes, underscores only)" >&2
    return 1
  fi
  return 0
}

sanitize_name() {
  local name="$1"
  [[ "$name" =~ [/\.\.\ ] ]] && return 1
  [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]] && return 1
  return 0
}

sanitize_yq_key() {
  local key="$1"
  [[ "$key" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  return 0
}

find_project_root() {
  local dir="${PROJECT_ROOT:-}"
  if [ -n "$dir" ] && [ -d "$dir" ]; then
    echo "$dir"
    return
  fi
  dir="$ROOT_DIR"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.opencode" ] || [ -d "$dir/.claude" ] || [ -d "$dir/.pi" ]; then
      echo "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  echo "Warning: no project root found (.opencode/.claude/.pi). Using $PWD." >&2
  echo "$PWD"
}

auto_pull_registry() {
  [ -d "$ROOT_DIR/.git" ] || return 0

  git -C "$ROOT_DIR" pull --ff-only 2>/dev/null || {
    echo "Warning: could not pull latest registry. Continuing with local version." >&2
  }
}

require_cmd() {
  for c in "$@"; do
    command -v "$c" &>/dev/null || { echo "Error: '$c' is required." >&2; exit 1; }
  done
}

load_env() {
  [ -f "$ENV_FILE" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    local key="${line%%=*}"
    local value="${line#*=}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ "$key" =~ ^(PATH|HOME|USER|SHELL|TERM|PWD|UID|GID|SHLVL)$ ]] && continue
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    if [[ "$value" == "~"* ]]; then
      value="${HOME}${value#\~}"
    fi
    export "$key=$value"
  done < "$ENV_FILE"
}

_base64url_encode() {
  if command -v base64 &>/dev/null; then
    base64 | tr '+/' '-_' | tr -d '=\n'
  elif command -v b64encode &>/dev/null; then
    b64encode -w 0 2>/dev/null | tr '+/' '-_' | tr -d '=\n'
  fi
}

generate_jwt() {
  local app_id="$1"
  local key_path="$2"

  if [ ! -f "$key_path" ]; then
    echo "Error: GitHub App private key not found at '$key_path'" >&2
    return 1
  fi

  local now
  now=$(date +%s)
  local exp=$((now + 600))

  local header
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | _base64url_encode)
  local payload
  payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$now" "$exp" "$app_id" | _base64url_encode)

  local signature
  signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$key_path" 2>/dev/null | _base64url_encode)

  if [ -z "$signature" ]; then
    echo "Error: failed to sign JWT with '$key_path'. Ensure it is a valid RSA PEM key." >&2
    return 1
  fi

  printf '%s.%s.%s' "$header" "$payload" "$signature"
}

_get_installation_id() {
  local jwt="$1"
  local owner_repo="$2"

  local owner
  owner=$(echo "$owner_repo" | cut -d'/' -f1)

  local response
  response=$(curl -fsSL -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/$owner/installation" 2>/dev/null || \
    curl -fsSL -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/users/$owner/installation" 2>/dev/null)

  if [ -z "$response" ]; then
    return 1
  fi

  echo "$response" | yq -r '.id' 2>/dev/null
}

_get_cached_token() {
  local cache_key="$1"
  local cache_file="/tmp/arm-token-${cache_key}"

  if [ -f "$cache_file" ]; then
    local cached
    cached=$(cat "$cache_file" 2>/dev/null)
    if [ -n "$cached" ]; then
      local expires_at
      expires_at=$(echo "$cached" | cut -d'|' -f2)
      local now
      now=$(date +%s)
      if [ "$now" -lt "$expires_at" ]; then
        echo "$cached" | cut -d'|' -f1
        return 0
      fi
    fi
    rm -f "$cache_file"
  fi
  return 1
}

_set_cached_token() {
  local cache_key="$1"
  local token="$2"
  local expires_at="$3"
  local cache_file="/tmp/arm-token-${cache_key}"
  echo "${token}|${expires_at}" > "$cache_file"
  chmod 600 "$cache_file"
}

get_token() {
  local contributor="$1"
  local owner_repo="$2"

  sanitize_yq_key "$contributor" || return 1

  local app_id_env app_key_env
  app_id_env=$(yq -r ".contributors.\"$contributor\".gh-app-id" "$CONTRIBUTORS" 2>/dev/null)
  app_key_env=$(yq -r ".contributors.\"$contributor\".gh-app-key" "$CONTRIBUTORS" 2>/dev/null)

  if [ -z "$app_id_env" ] || [ "$app_id_env" = "null" ] || \
     [ -z "$app_key_env" ] || [ "$app_key_env" = "null" ]; then
    echo "Error: GitHub App not configured for contributor '$contributor'. Set gh-app-id and gh-app-key in contributors.yaml" >&2
    return 1
  fi

  if ! [[ "$app_id_env" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || \
     ! [[ "$app_key_env" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "Error: invalid env var names in contributors.yaml for '$contributor'" >&2
    return 1
  fi

  local app_id="${!app_id_env:-}"
  local app_key_path="${!app_key_env:-}"

  if [ -z "$app_id" ] || [ -z "$app_key_path" ]; then
    echo "Error: GitHub App credentials not found. Set $app_id_env and $app_key_env in .env" >&2
    return 1
  fi

  local cache_key
  cache_key=$(echo -n "${app_id}-${owner_repo}" | shasum | cut -d' ' -f1)

  local cached_token
  cached_token=$(_get_cached_token "$cache_key") && {
    echo "$cached_token"
    return 0
  }

  local jwt
  jwt=$(generate_jwt "$app_id" "$app_key_path") || return 1

  local installation_id
  installation_id=$(_get_installation_id "$jwt" "$owner_repo") || {
    echo "Error: GitHub App is not installed on '$owner_repo'" >&2
    return 1
  }

  local token_response
  token_response=$(curl -fsSL -X POST \
    -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/$installation_id/access_tokens" 2>/dev/null)

  if [ -z "$token_response" ]; then
    echo "Error: failed to get installation token for '$owner_repo'" >&2
    return 1
  fi

  local token expires_at
  token=$(echo "$token_response" | yq -r '.token' 2>/dev/null)
  expires_at=$(echo "$token_response" | yq -r '.expires_at' 2>/dev/null)

  if [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "Error: invalid token response for '$owner_repo'" >&2
    return 1
  fi

  local expires_epoch
  if [[ "$OSTYPE" == "darwin"* ]]; then
    expires_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expires_at" "+%s" 2>/dev/null || echo "0")
  else
    expires_epoch=$(date -d "$expires_at" "+%s" 2>/dev/null || echo "0")
  fi

  local buffer=$((expires_epoch - 60))
  _set_cached_token "$cache_key" "$token" "$buffer"

  echo "$token"
}

find_in_registry() {
  local type="$1"
  local name="$2"
  local target_platform="${3:-}"

  local registry_key
  case "$type" in
    agent) registry_key="agents" ;;
    skill) registry_key="skills" ;;
    command) registry_key="commands" ;;
    prompt) registry_key="prompts" ;;
    *) return 1 ;;
  esac

  if [ "$type" = "agent" ]; then
    for contributor in $(yq '.registry.agents | keys | .[]' "$REGISTRY" 2>/dev/null); do
      sanitize_yq_key "$contributor" || continue
      if [ -n "$target_platform" ] && [ "$target_platform" != "default" ]; then
        src=$(yq -r ".registry.agents.\"$contributor\".\"$target_platform\".\"$name\".source" "$REGISTRY" 2>/dev/null)
        if [ -n "$src" ] && [ "$src" != "null" ]; then
          echo "$contributor|$target_platform|$src"
          return 0
        fi
      fi

      src=$(yq -r ".registry.agents.\"$contributor\".default.\"$name\".source" "$REGISTRY" 2>/dev/null)
      if [ -n "$src" ] && [ "$src" != "null" ]; then
        echo "$contributor|default|$src"
        return 0
      fi
    done
  else
    for contributor in $(yq ".registry.${registry_key} | keys | .[]" "$REGISTRY" 2>/dev/null); do
      sanitize_yq_key "$contributor" || continue
      src=$(yq -r ".registry.${registry_key}.\"$contributor\".\"$name\".source" "$REGISTRY" 2>/dev/null)
      if [ -n "$src" ] && [ "$src" != "null" ]; then
        echo "$contributor||$src"
        return 0
      fi
    done
  fi

  return 1
}

get_target_dir() {
  local platform="$1"
  local type="$2"
  local scope="$3"
  local key="local"
  [ "$scope" = "global" ] && key="global"

  local type_key
  case "$type" in
    agent) type_key="agents" ;;
    skill) type_key="skills" ;;
    command) type_key="commands" ;;
    prompt) type_key="prompts" ;;
    *) return 1 ;;
  esac

  local raw
  raw=$(yq -r ".default_dirs.\"$platform\".\"$type_key\"[] | select(.$key) | .$key" "$DIRS" 2>/dev/null)

  if [ -n "$raw" ] && [ "$raw" != "null" ]; then
    if [[ "$raw" != /* ]]; then
      local proj_root
      proj_root=$(find_project_root)
      echo "${proj_root}/${raw}"
    else
      echo "$raw"
    fi
  fi
}

get_all_installed() {
  local platform="$1"
  local scope="$2"

  for type in agent skill command prompt; do
    local target_dir
    target_dir=$(get_target_dir "$platform" "$type" "$scope")
    if [ -z "$target_dir" ] || [ "$target_dir" = "null" ] || [ ! -d "$target_dir" ]; then
      continue
    fi

    if [ "$type" = "agent" ]; then
      for file in "$target_dir"/*.md; do
        [ -f "$file" ] || continue
        local name
        name=$(basename "$file" .md)
        echo "$type:$name"
      done
    else
      for dir in "$target_dir"/*/; do
        [ -d "$dir" ] || continue
        local name
        name=$(basename "$dir")
        echo "$type:$name"
      done
    fi
  done
}

parse_github_url() {
  local url="$1"
  local path_after_tree
  if [[ "$url" == *"/blob/"* ]]; then
    path_after_tree=$(echo "$url" | sed 's|https://github.com/||' | sed 's|/blob/|/|')
  else
    path_after_tree=$(echo "$url" | sed 's|https://github.com/||' | sed 's|/tree/|/|')
  fi
  local owner=$(echo "$path_after_tree" | cut -d'/' -f1)
  local repo=$(echo "$path_after_tree" | cut -d'/' -f2)
  local branch=$(echo "$path_after_tree" | cut -d'/' -f3)
  local path=$(echo "$path_after_tree" | cut -d'/' -f4-)
  echo "$owner|$repo|$branch|$path"
}

validate_agent_file() {
  local path="$1"
  [ -f "$path" ] || return 1
  [ -s "$path" ] || { echo "Error: downloaded file is empty." >&2; return 1; }
  head -c 4096 "$path" | grep -qiE '<(!DOCTYPE|html|head|body)' && {
    echo "Error: received HTML instead of markdown. The file may not exist or the repo is private." >&2
    return 1
  }
  return 0
}

validate_skill_dir() {
  local path="$1"
  [ -d "$path" ] || return 1
  [ -n "$(ls -A "$path" 2>/dev/null)" ] || { echo "Error: downloaded skill folder is empty." >&2; return 1; }
  return 0
}

download_agent() {
  local source_url="$1"
  local token="$2"
  local out_path="$3"

  local parsed
  parsed=$(parse_github_url "$source_url")
  local owner=$(echo "$parsed" | cut -d'|' -f1)
  local repo=$(echo "$parsed" | cut -d'|' -f2)
  local branch=$(echo "$parsed" | cut -d'|' -f3)
  local path=$(echo "$parsed" | cut -d'|' -f4)

  local raw_url="https://raw.githubusercontent.com/$owner/$repo/$branch/$path"

  local curl_args=(-fsSL -o "$out_path" "$raw_url")
  if [ -n "$token" ]; then
    curl "${curl_args[@]}" -H "Authorization: token $token" || return 1
  else
    curl "${curl_args[@]}" || return 1
  fi

  validate_agent_file "$out_path"
}

download_skill() {
  local source_url="$1"
  local token="$2"
  local out_dir="$3"

  local parsed
  parsed=$(parse_github_url "$source_url")
  local owner=$(echo "$parsed" | cut -d'|' -f1)
  local repo=$(echo "$parsed" | cut -d'|' -f2)
  local branch=$(echo "$parsed" | cut -d'|' -f3)
  local path=$(echo "$parsed" | cut -d'|' -f4)

  local clone_url="https://github.com/$owner/$repo.git"
  local tmp_dir
  tmp_dir=$(mktemp -d)

  if [ -n "$token" ]; then
    local auth_url="https://x-access-token:${token}@github.com/${owner}/${repo}.git"
    GIT_TERMINAL_PROMPT=0 \
      git clone --depth 1 --sparse "$auth_url" "$tmp_dir/repo" 2>/dev/null || {
      rm -rf "$tmp_dir"
      return 1
    }
  else
    git clone --depth 1 --sparse "$clone_url" "$tmp_dir/repo" 2>/dev/null || {
      rm -rf "$tmp_dir"
      return 1
    }
  fi

  (cd "$tmp_dir/repo" && git sparse-checkout set "$path" 2>/dev/null)

  local result=0
  if [ -d "$tmp_dir/repo/$path" ]; then
    mkdir -p "$out_dir"
    rm -rf "${out_dir:?}/"* 2>/dev/null || true
    find "$tmp_dir/repo/$path" -mindepth 1 -maxdepth 1 -exec cp -r {} "$out_dir" \;
    validate_skill_dir "$out_dir" || result=$?
  else
    result=1
  fi

  rm -rf "$tmp_dir"
  return $result
}


