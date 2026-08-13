#!/usr/bin/env bash

# Resolve the real path of this script (handles symlinks)
AWS_TF="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

# break program if error is encountered
set -eo pipefail

# set up the local for the aws credentials file
declare -r aws_credentials_file="$HOME/.aws/credentials"

# message display function
msg() {
  local text="$1"
  local div_width="100"
  printf "%${div_width}s\n" ' ' | tr ' ' -
  printf "%s\n" "$text"
}

# function to confirm user selection
confirm() {
  local question="$1"
  while true; do
    msg "$question"
    read -p "[y]es or [n]o (default: no) : " -r answer
    case "$answer" in
      y | Y | yes | Yes | YES)
        return 0
        ;;
      n | N | no | No | *[[:blank:]]* | "")
        return 1
        ;;
      *)
        msg "Please answer [y]es or [n]o"
        ;;
    esac
  done
}

# function to check if terraform is installed and terraform version
check_terraform() {
  if command -v terraform &>/dev/null; then
    msg "Terraform is installed"
    terraform_version=$(terraform version -json | jq -r .terraform_version)
    echo "Terraform version $terraform_version"
  else
    echo "Terraform is not installed"
    exit 1
  fi
}

# function to check if awscli is installed and awscli version
check_awscli() {
  if command -v aws &>/dev/null; then
    msg "AWS is installed"
    aws_version=$(aws --version | awk '-F[ /]' '{print $2}')
    echo "AWS version $aws_version"
  else
    echo "AWS is not installed"
    exit 1
  fi
}

# function to check if awscli is configured
check_aws_credentials() {
  if [ -s "$aws_credentials_file" ]; then
    msg "AWS Credentials are configured"
  else
    echo "AWS Credentials are not configured"
    exit 1
  fi
}

# function to check aws profiles in configuration
extract_aws_profiles() {
  local i=1
  while read -r line; do
    profile_names[i]=$(echo "$line" | awk -F'[][]' '{print $2}')
    echo -e "$i) ${profile_names[i]}"
    ((i++))
  done < <(awk '/^\[/{print}' "$aws_credentials_file")
}

# function to select aws profile
select_aws_profile() {
  local profile_count=${#profile_names[@]}
  local selection
  read -r -p "Select an AWS profile by number (1-$profile_count): " selection

  # Validate the selection
  if [[ $selection =~ ^[0-9]+$ ]] && ((selection >= 1 && selection <= profile_count)); then
    selected_aws_profile=${profile_names[selection]}
    echo "AWS profile selected is : $selected_aws_profile"
  else
    echo "Option is Invalid. Kindly select the displayed profiles"
    select_aws_profile
  fi
}

directory_structure_template() {
  root_directory=$1

  # Define an array of directory names for scripts
  scripts_dir=(
    "amazon-linux-2"
    "debian"
    "rhel"
    "ubuntu"
  )

  # Define an array of module names
  modules=(
    "compute"
    "containers"
    "database"
    "management"
    "network"
    "notifications"
    "scaling"
    "security"
    "severless"
    "storage"
    "traffic"
  )

  # Define an array of module filenames to create
  module_files=(
    "main.tf"
    "outputs.tf"
    "provider.tf"
    "variables.tf"
  )

  # Define an array of root filenames to create
  root_files=(
    "main.tf"
    "outputs.tf"
    "variables.tf"
    "provider.tf"
    "terraform.tfvars"
    ".gitignore"
    "README.md"
  )

  # Create the files in the root directory
  for file in "${root_files[@]}"; do
    root_name="$root_directory"
    if [ ! -d "$root_name" ]; then
      mkdir -p "$root_name"
    fi
    touch "$root_name/$file"
  done

  # Create the directories for scripts module
  for module in "${scripts_dir[@]}"; do
    script_dir="$root_directory/cloud-init/$module"
    mkdir -p "$script_dir"
  done

  # Create the directories and files in each module
  for module in "${modules[@]}"; do
    module_dir="$root_directory/modules/$module"
    mkdir -p "$module_dir"

    # create sub-directory for templates
    templates_dir="$module_dir/templates"
    mkdir -p "$templates_dir"

    # create files for the modules
    for file in "${module_files[@]}"; do
      touch "$module_dir/$file"
    done
  done
}

create_terraform_infrastructure() {
  if confirm "Would you like to create your workspace in this directory"; then
    while true; do
      read -r -p "Enter the name of your workspace (no spaces allowed): " workspace_name
      # check if the workspace exist
      if [[ -d "$workspace_name" ]]; then
        echo "$workspace_name already exist"
        echo "Use another name"
      elif [[ ! "$workspace_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Invalid workspace name."
      else
        directory_structure_template "$workspace_name"
        break
      fi
    done
  fi
}

provider_file_append() {
  # Define provider templates
  local provider_a="$AWS_TF/provider_template_1.txt"
  local provider_b="$AWS_TF/provider_template_2.txt"

  # Select template based on AWS profile
  case "$selected_aws_profile" in
    ericngigi)
      echo "Appending provider template for profile A: $provider_a"
      cat "$provider_a" >>"$workspace_name/provider.tf"
      ;;
    saferiderkenya-ericngigi)
      echo "Appending provider template for profile B: $provider_b"
      cat "$provider_b" >>"$workspace_name/provider.tf"
      ;;
    localstack)
      echo "No specific provider template for profile '$selected_aws_profile', using default"
      cat "$AWS_TF/provider_template_default.txt" >>"$workspace_name/provider.tf"
      ;;
  esac
}

gitignore_file_append() {
  # Define gitignore template
  local gitignore_template="$AWS_TF/gitignore.txt"

  # Check if the gitignore file exist
  if confirm "Would you like to initialize the gitignore file to improve your workspace security"; then
    if [[ -f "$workspace_name/.gitignore" ]]; then
      echo "Appending to the Gitignore file"
      echo "Using gitignore template: $gitignore_template"
      cat "$gitignore_template" >>"$workspace_name/.gitignore"
    else
      echo "No Gitignore file found"
      exit 1
    fi
  else
    echo "Option is Invalid. Kindly select the displayed profiles"
    gitignore_file_append
  fi
}

initialize_workspace() {
  if confirm "Would you like to initialize the directory with the required provider file"; then
    if [[ -d "$workspace_name" ]]; then
      cd "$workspace_name" || exit
      if [[ "$selected_aws_profile" == "localstack" ]]; then
        echo "Running 'tflocal init' in the workspace"
        tflocal init
      else
        echo "Running 'terraform init' in the workspace"
        terraform init
      fi
    else
      echo "The workspace does not exit"
    fi
  else
    echo "Exiting application without performing initialization"
    exit 1
  fi
}

# function to display logo
print_logo() {
  cat <<'EOF'
   _____                    __                      ______                   _          _ 
|_   _|                  / _|                     |  _  \                 | |        | |
  | | ___ _ __ _ __ __ _| |_ ___  _ __ _ __ ___   | | | |___  ___ ___   __| | ___  __| |
  | |/ _ \ '__| '__/ _` |  _/ _ \| '__| '_ ` _ \  | | | / _ \/ __/ _ \ / _` |/ _ \/ _` |
  | |  __/ |  | | | (_| | || (_) | |  | | | | | | | |/ /  __/ (_| (_) | (_| |  __/ (_| |
  \_/\___|_|  |_|  \__,_|_| \___/|_|  |_| |_| |_| |___/ \___|\___\___/ \__,_|\___|\__,_|
                                                                                        

EOF
}

main() {
  print_logo
  msg "You are using Terraform Decoded: Optimizing your Development Environment"
  check_terraform
  check_awscli
  check_aws_credentials
  extract_aws_profiles
  select_aws_profile
  create_terraform_infrastructure
  provider_file_append
  gitignore_file_append
  initialize_workspace
}

main "$@"
