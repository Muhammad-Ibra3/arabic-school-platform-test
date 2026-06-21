#!/usr/bin/env bash
set -euo pipefail

KEY_NAME="ec2-test"
SSH_DIR="${HOME}/.ssh"
KEY_PATH="${SSH_DIR}/${KEY_NAME}"
PLATFORM=""

prompt_platform() {
  while true; do
    echo "Which machine are you using?"
    echo "  1) Mac"
    echo "  2) Linux / WSL"
    read -r -p "Enter 1 or 2: " choice

    case "${choice}" in
      1 | mac | Mac | MAC)
        PLATFORM="mac"
        return 0
        ;;
      2 | linux | Linux | wsl | WSL)
        PLATFORM="linux"
        return 0
        ;;
      *)
        echo "Invalid choice. Please enter 1 or 2."
        ;;
    esac
  done
}

ensure_ssh_dir() {
  cd "${HOME}"
  mkdir -p "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"
}

key_exists() {
  [[ -f "${KEY_PATH}" || -f "${KEY_PATH}.pub" ]]
}

remove_existing_key() {
  ssh-add -d "${KEY_PATH}" >/dev/null 2>&1 || true
  rm -f "${KEY_PATH}" "${KEY_PATH}.pub"
}

prompt_yes_no() {
  local prompt_text="$1"
  local answer=""

  while true; do
    read -r -p "${prompt_text} (yes/no): " answer
    case "${answer}" in
      yes | y | Y)
        return 0
        ;;
      no | n | N)
        return 1
        ;;
      *)
        echo "Please answer yes or no."
        ;;
    esac
  done
}

read_private_key() {
  local tmp_file
  tmp_file="$(mktemp)"

  echo
  echo "Paste the private SSH key content for ${KEY_NAME}."
  echo "When you are done, press Ctrl+D:"
  echo

  if ! cat >"${tmp_file}"; then
    rm -f "${tmp_file}"
    echo "No key content provided." >&2
    exit 1
  fi

  if ! grep -q "BEGIN.*PRIVATE KEY" "${tmp_file}" || ! grep -q "END.*PRIVATE KEY" "${tmp_file}"; then
    rm -f "${tmp_file}"
    echo "That does not look like a valid private key (expected BEGIN/END PRIVATE KEY markers)." >&2
    exit 1
  fi

  mv "${tmp_file}" "${KEY_PATH}"
  chmod 600 "${KEY_PATH}"
}

create_public_key() {
  if ssh-keygen -y -f "${KEY_PATH}" >"${KEY_PATH}.pub" 2>/dev/null; then
    chmod 644 "${KEY_PATH}.pub"
  else
    echo "Warning: could not derive a public key from the private key." >&2
  fi
}

add_key_to_agent() {
  if [[ "${PLATFORM}" == "mac" ]]; then
    if ssh-add --apple-use-keychain "${KEY_PATH}"; then
      echo "Added ${KEY_NAME} to the SSH agent and macOS keychain."
    else
      echo "Failed to add ${KEY_NAME} to the SSH agent/keychain." >&2
      exit 1
    fi
    return 0
  fi

  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    eval "$(ssh-agent -s)" >/dev/null
  fi

  if ssh-add "${KEY_PATH}"; then
    echo "Added ${KEY_NAME} to the SSH agent."
  else
    echo "Failed to add ${KEY_NAME} to the SSH agent." >&2
    exit 1
  fi
}

main() {
  prompt_platform
  ensure_ssh_dir

  if key_exists; then
    echo "An SSH key named ${KEY_NAME} already exists at ${KEY_PATH}."
    if prompt_yes_no "Delete the existing key and replace it"; then
      remove_existing_key
    else
      echo "Leaving the existing ${KEY_NAME} key in place."
      exit 0
    fi
  fi

  read_private_key
  create_public_key
  add_key_to_agent

  echo
  echo "Done. Private key: ${KEY_PATH}"
  if [[ -f "${KEY_PATH}.pub" ]]; then
    echo "Public key:  ${KEY_PATH}.pub"
  fi
}

main "$@"
