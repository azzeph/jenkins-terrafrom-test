// ---------------------------------------------------------------------------
// Jenkins declarative pipeline for the ai-libvirt Terraform project.
//
// On start the pipeline asks for a handful of parameters. The project name is
// the single source of truth: the network name, DNS domain and every VM
// hostname are derived from it (unless explicitly overridden).
//
// Example: PROJECT_NAME=tf, VM_COUNT=3, VM_NAME_PREFIX="" produces
//   network  tf-net
//   domain   tf.local
//   VMs      tf-node1, tf-node2, tf-node3   (10.10.0.11 .. 10.10.0.13)
// ---------------------------------------------------------------------------

pipeline {
    agent any

    parameters {
        // --- project --------------------------------------------------------
        string(name: 'PROJECT_NAME', defaultValue: 'tf',
               description: 'Logical project name. Drives network name, DNS domain and VM hostnames.')

        choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'],
               description: 'Terraform action to run. Default is `plan` — nothing is created until you choose apply.')

        // --- infrastructure -------------------------------------------------
        string(name: 'LIBVIRT_URI', defaultValue: 'qemu:///system',
               description: 'libvirt connection URI.')

        string(name: 'POOL_NAME', defaultValue: 'default',
               description: 'Storage pool for base image, overlays and cloud-init ISOs. If it does not exist it is created automatically (dir pool).')

        string(name: 'STORAGE_POOL_DIR', defaultValue: '/var/lib/libvirt/images',
               description: 'Parent directory for an auto-created dedicated storage pool.')

        string(name: 'BASE_IMAGE_URL', defaultValue: 'https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img',
               description: 'Cloud image used as backing store for every VM.')

        string(name: 'VM_DISK_SIZE', defaultValue: '21474836480',
               description: 'Overlay disk size in bytes (default 20 GiB).')

        // --- network --------------------------------------------------------
        string(name: 'NETWORK_NAME', defaultValue: '',
               description: 'Network name. Empty -> "<project>-net".')

        string(name: 'NETWORK_CIDR', defaultValue: '10.10.0.0/24',
               description: 'IPv4 CIDR of the virtual network.')

        string(name: 'NETWORK_GATEWAY', defaultValue: '10.10.0.1',
               description: 'Gateway / host address of the virtual network.')

        string(name: 'NETWORK_DOMAIN', defaultValue: '',
               description: 'DNS domain. Empty -> "<project>.local".')

        booleanParam(name: 'NETWORK_ISOLATION', defaultValue: false,
               description: 'Isolated network (no NAT). false = NAT to the host network.')

        // --- VMs ------------------------------------------------------------
        string(name: 'VM_COUNT', defaultValue: '2',
               description: 'Number of VMs to create (>= 2).')

        string(name: 'VM_NAME_PREFIX', defaultValue: '',
               description: 'Hostname prefix. Empty -> "<project>-node".')

        string(name: 'VM_IP_START_OFFSET', defaultValue: '11',
               description: 'Host part of the first VM address (11 -> x.x.x.11).')

        string(name: 'VM_DEFAULT_VCPU', defaultValue: '2',
               description: 'vCPUs per auto-generated VM.')

        string(name: 'VM_DEFAULT_MEMORY_MIB', defaultValue: '2048',
               description: 'Memory (MiB) per auto-generated VM.')

        // --- access ---------------------------------------------------------
        string(name: 'ADMIN_USER', defaultValue: 'ubuntu',
               description: 'Cloud-init admin user created on the VMs.')

        string(name: 'SSH_PUBLIC_KEY_PATH', defaultValue: '~/.ssh/id_ed25519.pub',
               description: 'Path to the SSH public key injected into every VM.')

        // --- behaviour ------------------------------------------------------
        booleanParam(name: 'AUTO_APPROVE', defaultValue: false,
               description: 'Skip the Jenkins Confirm stage. Terraform itself always runs with -auto-approve (Jenkins is not a TTY), so this only controls the interactive gate: false = the Confirm stage waits for you to press Proceed.')

        booleanParam(name: 'PLAN_WITH_DETAILS', defaultValue: false,
               description: 'Show a detailed plan (-out + `terraform show`).')

        // --- ansible --------------------------------------------------------
        booleanParam(name: 'RUN_ANSIBLE', defaultValue: true,
               description: 'After a successful apply, run Ansible against the VMs. Skipped automatically for ACTION=plan/destroy (nothing to configure). The inventory environment is taken from the git branch name (ansible/inventory/<branch>/hosts.ini).')

        string(name: 'ANSIBLE_PLAYBOOK', defaultValue: 'ansible/site.yml',
               description: 'Playbook to run (relative to the repository root).')

        booleanParam(name: 'ANSIBLE_DYNAMIC_INVENTORY', defaultValue: true,
               description: 'Use scripts/terraform_inventory.py directly as an executable (dynamic) inventory, built from terraform output for the branch environment, instead of the generated per-branch hosts.ini file.')

        string(name: 'ANSIBLE_LIMIT', defaultValue: '',
               description: 'Ansible --limit (host or group). Empty -> all hosts of the branch environment.')

        string(name: 'ANSIBLE_TAGS', defaultValue: '',
               description: 'Ansible --tags (comma separated). Empty -> all tasks.')

        string(name: 'ANSIBLE_EXTRA_VARS', defaultValue: '',
               description: 'Extra vars for ansible-playbook as key=value pairs.')

        booleanParam(name: 'ANSIBLE_CHECK_MODE', defaultValue: false,
               description: 'Run Ansible in check (dry-run) mode.')

        booleanParam(name: 'ANSIBLE_MANUAL_APPROVE', defaultValue: true,
               description: 'Pause at a manual confirmation stage before running Ansible (apply/destroy are already gated by Confirm).')
    }

    environment {
        TF_IN_AUTOMATION = 'true'
        TF_INPUT         = '0'
        PROJECT          = "${params.PROJECT_NAME}"
        WORKDIR          = "${env.WORKSPACE}"

        // ansible-core >= 2.13: the old 'yaml' stdout callback was removed.
        ANSIBLE_FORCE_COLOR            = '1'
        ANSIBLE_HOST_KEY_CHECKING      = 'False'
        ANSIBLE_STDOUT_CALLBACK        = 'default'
        ANSIBLE_CALLBACK_RESULT_FORMAT = 'yaml'
        ANSIBLE_INVENTORY_ROOT         = 'ansible/inventory'
        ANSIBLE_SCRIPT                 = 'scripts/terraform_inventory.py'
    }

    options {
        timestamps()
        ansiColor('xterm')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // ------------------------------------------------------------------
        // The Ansible environment is derived from the git branch name:
        //   main / feature/x  ->  ansible/inventory/main, ansible/inventory/feature-x
        // ------------------------------------------------------------------
        stage('Resolve environment') {
            steps {
                script {
                    def branch = env.BRANCH_NAME?.trim()
                    if (!branch) {
                        branch = sh(
                            script: 'git rev-parse --abbrev-ref HEAD 2>/dev/null || true',
                            returnStdout: true
                        ).trim()
                    }
                    if (!branch || branch == 'HEAD') {
                        branch = 'local'
                    }
                    // Same sanitisation as sanitize_branch() in
                    // scripts/terraform_inventory.py so the directory name matches.
                    def envName = branch.trim()
                        .replaceAll('[/\\\\ :]', '-')
                        .replaceAll('-{2,}', '-')
                        .replaceAll('^[-.]+|[-.]+$', '')
                    if (!envName) {
                        envName = 'local'
                    }
                    env.ANSIBLE_ENV             = envName
                    env.ANSIBLE_INVENTORY_DIR   = "${env.ANSIBLE_INVENTORY_ROOT}/${envName}"
                    env.ANSIBLE_INVENTORY       = "${env.ANSIBLE_INVENTORY_DIR}/hosts.ini"
                    echo "Branch '${branch}' -> Ansible environment '${envName}' (${env.ANSIBLE_INVENTORY})"
                }
            }
        }

        stage('Prepare tfvars') {
            steps {
                script {
                    def banner = [
                        '===============================================================',
                        ' Effective parameters for this run',
                        '===============================================================',
                        "  ACTION            : ${params.ACTION}",
                        "  PROJECT_NAME      : ${params.PROJECT_NAME}",
                        "  VM_COUNT          : ${params.VM_COUNT}",
                        "  VM_NAME_PREFIX    : '${params.VM_NAME_PREFIX}' (empty -> <project>-node)",
                        "  NETWORK_CIDR      : ${params.NETWORK_CIDR}",
                        "  NETWORK_ISOLATION : ${params.NETWORK_ISOLATION}",
                        "  AUTO_APPROVE      : ${params.AUTO_APPROVE}",
                        '===============================================================',
                        " If these are not what you expected, abort and re-run this job",
                        " via 'Build with Parameters'.",
                        '===============================================================',
                    ].join('\n')
                    echo banner

                    // Generate a terraform.tfvars from the pipeline parameters.
                    def tfvars = [
                        "project_name     = \"${params.PROJECT_NAME}\"",
                        "libvirt_uri      = \"${params.LIBVIRT_URI}\"",
                        "pool_name        = \"${params.POOL_NAME}\"",
                        "storage_pool_dir = \"${params.STORAGE_POOL_DIR}\"",
                        "base_image_url   = \"${params.BASE_IMAGE_URL}\"",
                        "vm_disk_size     = ${params.VM_DISK_SIZE}",
                        "network_name     = \"${params.NETWORK_NAME}\"",
                        "network_cidr     = \"${params.NETWORK_CIDR}\"",
                        "network_gateway  = \"${params.NETWORK_GATEWAY}\"",
                        "network_domain   = \"${params.NETWORK_DOMAIN}\"",
                        "network_isolation = ${params.NETWORK_ISOLATION}",
                        "vm_count              = ${params.VM_COUNT}",
                        "vm_name_prefix        = \"${params.VM_NAME_PREFIX}\"",
                        "vm_ip_start_offset    = ${params.VM_IP_START_OFFSET}",
                        "vm_default_vcpu       = ${params.VM_DEFAULT_VCPU}",
                        "vm_default_memory_mib = ${params.VM_DEFAULT_MEMORY_MIB}",
                        "admin_user          = \"${params.ADMIN_USER}\"",
                        "ssh_public_key_path = \"${params.SSH_PUBLIC_KEY_PATH}\"",
                    ].join('\n') + '\n'

                    writeFile file: 'terraform.tfvars', text: tfvars
                    sh 'cat terraform.tfvars'
                }
            }
        }

        stage('Terraform init') {
            steps {
                sh 'terraform init -input=false -upgrade'
            }
        }

        stage('Terraform validate') {
            steps {
                sh 'terraform validate'
            }
        }

        stage('Terraform plan') {
            steps {
                script {
                    if (params.PLAN_WITH_DETAILS) {
                        sh 'terraform plan -input=false -lock=false -out=tfplan'
                        sh 'terraform show -no-color tfplan > plan.txt || true'
                        archiveArtifacts artifacts: 'plan.txt', allowEmptyArchive: true
                    } else {
                        sh 'terraform plan -input=false -lock=false'
                    }
                }
            }
        }

        stage('Confirm') {
            when {
                expression { params.ACTION == 'apply' || params.ACTION == 'destroy' }
            }
            steps {
                script {
                    if (params.AUTO_APPROVE) {
                        echo "AUTO_APPROVE=true -> skipping confirmation for '${params.ACTION}'."
                    } else {
                        // Blocks the build until a human clicks Proceed / Abort.
                        input(
                            message: "Ready to run 'terraform ${params.ACTION}' for project '${params.PROJECT_NAME}' " +
                                     "(${params.VM_COUNT} VM(s), network ${params.NETWORK_CIDR}). Proceed?",
                            ok: 'Proceed',
                            submitter: '',
                            submitterParameter: '',
                            parameters: []
                        )
                    }
                }
            }
        }

        stage('Terraform apply') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                script {
                    // The approval already happened in the 'Confirm' stage (or was
                    // skipped via AUTO_APPROVE). Output is not a TTY here, so an
                    // interactive prompt is impossible -> always -auto-approve.
                    sh 'terraform apply -input=false -auto-approve -lock=false'
                }
            }
        }

        stage('Terraform destroy') {
            when { expression { params.ACTION == 'destroy' } }
            steps {
                script {
                    sh 'terraform destroy -input=false -auto-approve -lock=false'
                }
            }
        }

        stage('Collect outputs') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                script {
                    sh '''
                        set +e
                        echo "================ Terraform outputs ================"
                        terraform output
                        echo "================ VM hostnames / IPs ==============="
                        terraform output -json vms 2>/dev/null | jq -r 'to_entries[] | "  \\(.key): \\(.value.hostname) -> \\(.value.ip) (\\(.value.mac))"' || true
                        echo "================ SSH commands ====================="
                        terraform output -json ssh_commands 2>/dev/null | jq -r 'to_entries[] | "  \\(.key): \\(.value)"' || true
                        terraform output -json ssh_commands 2>/dev/null | jq -r 'to_entries[] | .value' > ssh_commands.txt || true
                    '''
                    archiveArtifacts artifacts: 'ssh_commands.txt', allowEmptyArchive: true
                }
            }
        }
        // ------------------------------------------------------------------
        // ANSIBLE
        // ------------------------------------------------------------------
        stage('Ansible: generate inventory') {
            // Only meaningful after apply: on destroy the VMs no longer exist.
            when { expression { params.RUN_ANSIBLE && params.ACTION == 'apply' } }
            steps {
                script {
                    sh """
                        set -e
                        chmod +x '${env.ANSIBLE_SCRIPT}' 2>/dev/null || true
                        python3 '${env.ANSIBLE_SCRIPT}' \\
                            --terraform-dir "${env.WORKSPACE}" \\
                            --branch '${env.ANSIBLE_ENV}' \\
                            --inventory-root '${env.ANSIBLE_INVENTORY_ROOT}'
                        echo '---------------- ${env.ANSIBLE_INVENTORY} ----------------'
                        cat '${env.ANSIBLE_INVENTORY}'
                        echo '-----------------------------------------------------------'
                    """
                }
            }
        }

        stage('Ansible: manual approval') {
            when { expression { params.RUN_ANSIBLE && params.ACTION == 'apply' && params.ANSIBLE_MANUAL_APPROVE } }
            steps {
                script {
                    def resp = input(
                        message: "Run Ansible for environment '${env.ANSIBLE_ENV}' " +
                                 "(inventory ${env.ANSIBLE_INVENTORY}). Adjust the options and press Proceed, or Abort.",
                        ok: 'Run Ansible',
                        submitter: '',
                        submitterParameter: 'APPROVED_BY',
                        parameters: [
                            string(name: 'PLAYBOOK',
                                   defaultValue: params.ANSIBLE_PLAYBOOK ?: 'ansible/site.yml',
                                   description: 'Playbook (relative to the repository root).'),
                            string(name: 'LIMIT',
                                   defaultValue: params.ANSIBLE_LIMIT ?: '',
                                   description: '--limit: host or group (empty = all hosts of this environment).'),
                            string(name: 'TAGS',
                                   defaultValue: params.ANSIBLE_TAGS ?: '',
                                   description: '--tags (comma separated, empty = all tasks).'),
                            string(name: 'SKIP_TAGS',
                                   defaultValue: '',
                                   description: '--skip-tags (comma separated, optional).'),
                            text(name: 'EXTRA_VARS',
                                 defaultValue: params.ANSIBLE_EXTRA_VARS ?: '',
                                 description: '--extra-vars (key=value key2=value2, optional).'),
                            booleanParam(name: 'CHECK_MODE',
                                         defaultValue: params.ANSIBLE_CHECK_MODE,
                                         description: 'Dry run (--check).'),
                            booleanParam(name: 'DYNAMIC_INVENTORY',
                                         defaultValue: params.ANSIBLE_DYNAMIC_INVENTORY,
                                         description: 'Use the dynamic inventory script instead of the generated hosts.ini.'),
                            string(name: 'FORKS',
                                   defaultValue: '',
                                   description: '--forks (empty = ansible.cfg default).'),
                            booleanParam(name: 'CONFIRM', defaultValue: true,
                                         description: 'Must stay checked to run Ansible. Uncheck to skip.')
                        ]
                    )

                    if (!resp.CONFIRM) {
                        echo 'Ansible run NOT confirmed - skipping.'
                        env.ANSIBLE_SKIPPED = 'true'
                        return
                    }

                    echo "Ansible approved by: ${resp.APPROVED_BY ?: 'unknown'}"

                    env.ANSIBLE_PLAYBOOK_RUN    = resp.PLAYBOOK
                    env.ANSIBLE_LIMIT_RUN       = resp.LIMIT
                    env.ANSIBLE_TAGS_RUN        = resp.TAGS
                    env.ANSIBLE_SKIP_TAGS_RUN   = resp.SKIP_TAGS
                    env.ANSIBLE_EXTRA_VARS_RUN  = resp.EXTRA_VARS
                    env.ANSIBLE_CHECK_MODE_RUN  = resp.CHECK_MODE.toString()
                    env.ANSIBLE_DYNAMIC_RUN     = resp.DYNAMIC_INVENTORY.toString()
                    env.ANSIBLE_FORKS_RUN       = resp.FORKS
                    env.ANSIBLE_APPROVED        = 'true'
                }
            }
        }

        stage('Ansible: run playbook') {
            when {
                expression {
                    params.RUN_ANSIBLE &&
                    params.ACTION == 'apply' &&
                    (params.ANSIBLE_MANUAL_APPROVE ? env.ANSIBLE_APPROVED == 'true' : true)
                }
            }
            steps {
                script {
                    // Manual stage values win; otherwise fall back to job params.
                    def playbook  = env.ANSIBLE_PLAYBOOK_RUN    ?: params.ANSIBLE_PLAYBOOK
                    def limit     = env.ANSIBLE_LIMIT_RUN       ?: params.ANSIBLE_LIMIT
                    def tags      = env.ANSIBLE_TAGS_RUN        ?: params.ANSIBLE_TAGS
                    def skipTags  = env.ANSIBLE_SKIP_TAGS_RUN
                    def extraVars = env.ANSIBLE_EXTRA_VARS_RUN  ?: params.ANSIBLE_EXTRA_VARS
                    def checkMode = env.ANSIBLE_CHECK_MODE_RUN  ? env.ANSIBLE_CHECK_MODE_RUN.toBoolean() : params.ANSIBLE_CHECK_MODE
                    def dynInv    = env.ANSIBLE_DYNAMIC_RUN     ? env.ANSIBLE_DYNAMIC_RUN.toBoolean()    : params.ANSIBLE_DYNAMIC_INVENTORY
                    def forks     = env.ANSIBLE_FORKS_RUN

                    def inventory = dynInv
                        ? "${env.WORKSPACE}/${env.ANSIBLE_SCRIPT}"
                        : "${env.WORKSPACE}/${env.ANSIBLE_INVENTORY}"

                    // ansible-playbook runs from ansible/, so strip the prefix.
                    def pb = (playbook ?: 'ansible/site.yml').trim()
                    if (pb.startsWith('ansible/')) { pb = pb.substring('ansible/'.length()) }

                    def args = []
                    // Expose the environment name to the playbook so tasks can
                    // behave per branch (e.g. "{{ env_name }}" in group_vars).
                    args << "-e 'env_name=${env.ANSIBLE_ENV}'"
                    if (limit?.trim())     { args << "--limit '${limit.trim()}'" }
                    if (tags?.trim())      { args << "--tags '${tags.trim()}'" }
                    if (skipTags?.trim())  { args << "--skip-tags '${skipTags.trim()}'" }
                    if (extraVars?.trim()) { args << "--extra-vars '${shellEscape(extraVars.trim())}'" }
                    if (forks?.trim())     { args << "--forks '${forks.trim()}'" }
                    if (checkMode)         { args << '--check' }

                    echo "Environment: ${env.ANSIBLE_ENV}"
                    echo "Inventory  : ${inventory}"
                    echo "Playbook   : ${pb}"
                    echo "Options    : ${args.join(' ')}"

                    sh """
                        set -e
                        cd 'ansible'
                        ansible-playbook -i '${inventory}' ${args.join(' ')} '${pb}'
                    """
                }
            }
        }
    }

    post {
        always {
            sh 'terraform output -json > tf_outputs.json 2>/dev/null || true'
            // NOTE: keep the workspace. terraform.tfstate lives here and deleting
            // the workspace would orphan every VM/network the pipeline created.
            // For a shared/robust setup, configure a remote backend instead
            // (see README) and then you may safely enable cleanWs().
            archiveArtifacts artifacts: 'tf_outputs.json, ssh_commands.txt, terraform.tfstate*, .terraform.lock.hcl', allowEmptyArchive: true
            archiveArtifacts artifacts: 'ansible/inventory/**/hosts.ini', allowEmptyArchive: true
        }
        success {
            echo 'Pipeline finished successfully.'
        }
        failure {
            echo 'Pipeline FAILED.'
        }
    }
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

// Escape single quotes so a value can be embedded in a single-quoted shell string.
def shellEscape(String s) {
    return s.replace("'", "'" + (char) 92 + "''")
}
