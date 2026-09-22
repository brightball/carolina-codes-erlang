#!/usr/bin/env bash
# Prepare/restore the Gitea CI workspace without Node or an OCI push.
#
# erlang:27-slim has no Node, so actions/upload-artifact cannot run inside
# the job container. v4 also treats Gitea as GHES and aborts. This helper
# packs the workspace plus rebar3/gitleaks (and apt .debs when present) and
# talks to Gitea's artifact v3 API with OTP httpc — curl is not in the
# check-job image until those .debs are restored.
set -euo pipefail

ARTIFACT_NAME="${CI_ENV_ARTIFACT_NAME:-prepared-env}"
TAR_PATH="${CI_ENV_TAR:-/tmp/prepared-env.tar.gz}"
BIN_DIR="${CI_ENV_BIN:-/usr/local/bin}"

json_string() {
  key="$1"
  file="$2"
  http_escript json-string "$file" "$key"
}

artifact_token() {
  t="${ACTIONS_RUNTIME_TOKEN:-${GITHUB_TOKEN:-${GITEA_TOKEN:-}}}"
  if [ -z "$t" ]; then
    echo "missing artifact token (ACTIONS_RUNTIME_TOKEN/GITHUB_TOKEN)" >&2
    exit 1
  fi
  printf '%s' "$t"
}

artifact_base() {
  if [ -n "${ACTIONS_RUNTIME_URL:-}" ]; then
    printf '%s' "${ACTIONS_RUNTIME_URL%/}"
    return
  fi
  if [ -z "${GITHUB_SERVER_URL:-}" ]; then
    echo "missing ACTIONS_RUNTIME_URL or GITHUB_SERVER_URL" >&2
    exit 1
  fi
  printf '%s' "${GITHUB_SERVER_URL%/}/api/actions_pipeline"
}

rewrite_runtime_url() {
  url="$1"
  case "$url" in
    *_apis/*)
      suffix="${url#*_apis/}"
      printf '%s/_apis/%s' "$(artifact_base)" "$suffix"
      ;;
    /*)
      printf '%s%s' "$(artifact_base)" "${url#/api/actions_pipeline}"
      ;;
    *)
      printf '%s' "$url"
      ;;
  esac
}

workspace_dir() {
  printf '%s' "${GITHUB_WORKSPACE:-$(pwd)}"
}

find_tool() {
  name="$1"
  if [ -x "${BIN_DIR}/${name}" ]; then
    printf '%s' "${BIN_DIR}/${name}"
    return
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return
  fi
  if [ -x "/usr/local/bin/${name}" ]; then
    printf '%s' "/usr/local/bin/${name}"
    return
  fi
  echo "missing tool: $name" >&2
  exit 1
}

# OTP httpc — works in erlang:27-slim with no curl/openssl/python/node.
http_escript() {
  es="${TMPDIR:-/tmp}/ci-env-http.escript"
  if [ ! -f "$es" ]; then
    cat >"$es" <<'ESCRIPT'
#!/usr/bin/env escript
%% -*- erlang -*-
main([Op | Args]) ->
    {ok, _} = application:ensure_all_started(inets),
    {ok, _} = application:ensure_all_started(ssl),
    try dispatch(Op, Args) of
        ok -> halt(0)
    catch
        Class:Reason:Stack ->
            io:format(standard_error, "~p:~p~n~p~n", [Class, Reason, Stack]),
            halt(1)
    end.

dispatch("json-string", [File, Key]) ->
    {ok, Bin} = file:read_file(File),
    io:format("~s", [json_get(Bin, list_to_binary(Key))]);
dispatch("md5-b64", [File]) ->
    {ok, Bin} = file:read_file(File),
    io:format("~s", [base64:encode(crypto:hash(md5, Bin))]);
dispatch("get", [Url, Out]) ->
    ok = file:write_file(Out, http_req(get, Url, [], undefined));
dispatch("put-file", [Url, In]) ->
    {ok, Body} = file:read_file(In),
    Size = integer_to_list(byte_size(Body)),
    Md5 = binary_to_list(base64:encode(crypto:hash(md5, Body))),
    Last = integer_to_list(byte_size(Body) - 1),
    Headers = [
        {"x-actions-results-md5", Md5},
        {"x-tfs-filelength", Size},
        {"content-range", "bytes 0-" ++ Last ++ "/" ++ Size}
    ],
    _ = http_req(put, Url, Headers, Body),
    ok;
dispatch("post-json", [Url, JsonFile, Out]) ->
    {ok, Json} = file:read_file(JsonFile),
    Body = http_req(post, Url, [{"Content-Type", "application/json"}], Json),
    ok = file:write_file(Out, Body);
dispatch("patch", [Url]) ->
    _ = http_req(patch, Url, [], <<>>),
    ok.

http_req(Method, Url0, ExtraHeaders, Body) ->
    Token = first_env(["ACTIONS_RUNTIME_TOKEN", "GITHUB_TOKEN", "GITEA_TOKEN"]),
    Auth =
        case Token of
            "" -> [];
            _ -> [{"Authorization", "Bearer " ++ Token}]
        end,
    Headers = Auth ++ ExtraHeaders,
    HttpOpts = [{ssl, [{verify, verify_none}]}, {timeout, infinity}, {connect_timeout, 30000}],
    Url = Url0,
    Request =
        case Body of
            undefined -> {Url, Headers};
            _ ->
                CT = content_type(ExtraHeaders),
                {Url, Headers, CT, Body}
        end,
    case httpc:request(Method, Request, HttpOpts, [{body_format, binary}]) of
        {ok, {{_, Code, _}, _, Resp}} when Code >= 200, Code < 300 ->
            Resp;
        {ok, {{_, Code, Reason}, _, Resp}} ->
            error({http_error, Code, Reason, Resp});
        Other ->
            error({http_error, Other})
    end.

content_type(Headers) ->
    case lists:keyfind("Content-Type", 1, Headers) of
        {_, CT} -> CT;
        false -> "application/octet-stream"
    end.

first_env([]) ->
    "";
first_env([Name | Rest]) ->
    case os:getenv(Name) of
        false -> first_env(Rest);
        "" -> first_env(Rest);
        Val -> Val
    end.

json_get(Bin, Key) ->
    case find_key(json:decode(Bin), Key) of
        undefined -> <<>>;
        V when is_binary(V) -> V;
        V when is_list(V) -> list_to_binary(V);
        Other -> iolist_to_binary(io_lib:format("~p", [Other]))
    end.

find_key(Map, Key) when is_map(Map) ->
    case maps:find(Key, Map) of
        {ok, V} -> V;
        error -> first_defined([find_key(V, Key) || V <- maps:values(Map)])
    end;
find_key(List, Key) when is_list(List) ->
    first_defined([find_key(V, Key) || V <- List]);
find_key(_, _) ->
    undefined.

first_defined([]) ->
    undefined;
first_defined([undefined | Rest]) ->
    first_defined(Rest);
first_defined([V | _]) ->
    V.
ESCRIPT
  fi
  escript "$es" "$@"
}

cmd_install() {
  echo "installing rebar3 3.25.1 and gitleaks 8.30.1"
  mkdir -p "$BIN_DIR"
  curl -fsSL -o "${BIN_DIR}/rebar3" https://github.com/erlang/rebar3/releases/download/3.25.1/rebar3
  chmod +x "${BIN_DIR}/rebar3"
  curl -sSfL https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz |
    tar -xz -C "$BIN_DIR" gitleaks
  chmod +x "${BIN_DIR}/gitleaks"
}

cmd_pack() {
  ws="$(workspace_dir)"
  rebar3_src="$(find_tool rebar3)"
  gitleaks_src="$(find_tool gitleaks)"
  stage="$(mktemp -d)"
  cleanup() { rm -rf "$stage"; }
  trap cleanup EXIT
  mkdir -p "$stage/workspace" "$stage/bin" "$stage/debs"
  tar -C "$ws" --exclude='./prepared-env.tar.gz' --exclude='./.ci-env' -cf - . |
    tar -C "$stage/workspace" -xf -
  cp -a "$rebar3_src" "$stage/bin/rebar3"
  cp -a "$gitleaks_src" "$stage/bin/gitleaks"
  chmod +x "$stage/bin/rebar3" "$stage/bin/gitleaks"
  if ls /var/cache/apt/archives/*.deb >/dev/null 2>&1; then
    cp -a /var/cache/apt/archives/*.deb "$stage/debs/"
  fi
  mkdir -p "$(dirname "$TAR_PATH")"
  tar -C "$stage" -czf "$TAR_PATH" workspace bin debs
  trap - EXIT
  cleanup
  echo "packed $TAR_PATH"
}

cmd_unpack() {
  ws="$(workspace_dir)"
  if [ ! -f "$TAR_PATH" ]; then
    echo "missing tarball $TAR_PATH" >&2
    exit 1
  fi
  stage="$(mktemp -d)"
  cleanup() { rm -rf "$stage"; }
  trap cleanup EXIT
  tar -C "$stage" -xzf "$TAR_PATH"
  mkdir -p "$ws" "$BIN_DIR"
  tar -C "$stage/workspace" -cf - . | tar -C "$ws" -xf -
  cp -a "$stage/bin/." "$BIN_DIR/"
  chmod +x "$BIN_DIR/rebar3" "$BIN_DIR/gitleaks"
  if ls "$stage/debs"/*.deb >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    export DEBIAN_FRONTEND=noninteractive
    dpkg --force-depends --install "$stage/debs"/*.deb
    hash -r || true
  fi
  trap - EXIT
  cleanup
  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$BIN_DIR" >>"$GITHUB_PATH"
  fi
  export PATH="${BIN_DIR}:${PATH}"
  echo "restored workspace=$ws bin=$BIN_DIR"
}

cmd_upload() {
  if [ ! -f "$TAR_PATH" ]; then
    echo "missing tarball $TAR_PATH" >&2
    exit 1
  fi
  if [ -z "${GITHUB_RUN_ID:-}" ]; then
    echo "missing GITHUB_RUN_ID" >&2
    exit 1
  fi
  token="$(artifact_token)"
  export ACTIONS_RUNTIME_TOKEN="$token"
  base="$(artifact_base)"
  create_url="${base}/_apis/pipelines/workflows/${GITHUB_RUN_ID}/artifacts?api-version=6.0-preview"
  req="$(mktemp)"
  resp="$(mktemp)"
  printf '{"Type":"actions_storage","Name":"%s"}' "$ARTIFACT_NAME" >"$req"
  http_escript post-json "$create_url" "$req" "$resp"
  upload_url="$(json_string fileContainerResourceUrl "$resp")"
  rm -f "$req" "$resp"
  if [ -z "$upload_url" ]; then
    echo "artifact create did not return fileContainerResourceUrl" >&2
    exit 1
  fi
  upload_url="$(rewrite_runtime_url "$upload_url")"
  filename="$(basename "$TAR_PATH")"
  put_url="${upload_url}?itemPath=${ARTIFACT_NAME}%2F${filename}"
  http_escript put-file "$put_url" "$TAR_PATH"
  http_escript patch \
    "${base}/_apis/pipelines/workflows/${GITHUB_RUN_ID}/artifacts?api-version=6.0-preview&artifactName=${ARTIFACT_NAME}"
  echo "uploaded artifact ${ARTIFACT_NAME}"
}

cmd_download() {
  if [ -z "${GITHUB_RUN_ID:-}" ]; then
    echo "missing GITHUB_RUN_ID" >&2
    exit 1
  fi
  token="$(artifact_token)"
  export ACTIONS_RUNTIME_TOKEN="$token"
  base="$(artifact_base)"
  list_url="${base}/_apis/pipelines/workflows/${GITHUB_RUN_ID}/artifacts?api-version=6.0-preview"
  resp="$(mktemp)"
  http_escript get "$list_url" "$resp"
  container_url="$(json_string fileContainerResourceUrl "$resp")"
  rm -f "$resp"
  if [ -z "$container_url" ]; then
    echo "artifact list did not return fileContainerResourceUrl" >&2
    exit 1
  fi
  container_url="$(rewrite_runtime_url "$container_url")"
  files="$(mktemp)"
  http_escript get "${container_url}?itemPath=${ARTIFACT_NAME}" "$files"
  content_url="$(json_string contentLocation "$files")"
  item_path="$(json_string path "$files")"
  rm -f "$files"
  if [ -z "$content_url" ]; then
    echo "artifact download_url did not return contentLocation" >&2
    exit 1
  fi
  content_url="$(rewrite_runtime_url "$content_url")"
  mkdir -p "$(dirname "$TAR_PATH")"
  encoded_path="$(printf '%s' "$item_path" | sed 's|/|%2F|g')"
  http_escript get "${content_url}?itemPath=${encoded_path}" "$TAR_PATH"
  echo "downloaded $TAR_PATH"
}

cmd_prepare() {
  if [ "${CI_ENV_SKIP_INSTALL:-}" != "1" ]; then
    cmd_install
  fi
  cmd_pack
  cmd_upload
}

cmd_restore() {
  echo "restoring prepared environment"
  cmd_download
  cmd_unpack
}

usage() {
  echo "usage: $0 prepare|restore|install|pack|unpack|upload|download" >&2
  exit 2
}

cmd="${1:-}"
case "$cmd" in
  prepare) cmd_prepare ;;
  restore) cmd_restore ;;
  install) cmd_install ;;
  pack) cmd_pack ;;
  unpack) cmd_unpack ;;
  upload) cmd_upload ;;
  download) cmd_download ;;
  *) usage ;;
esac
