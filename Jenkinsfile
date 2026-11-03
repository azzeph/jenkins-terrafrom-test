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

        choice(name: 'ACTION', choices: ['apply', 'plan', 'destroy'],
               description: 'Terraform action to run.')

        // --- infrastructure -------------------------------------------------
        string(name: 'LIBVIRT_URI', defaultValue: 'qemu:///system',
               description: 'libvirt connection URI.')

        string(name: 'POOL_NAME', defaultValue: 'default',
               description: 'Storage pool for base image, overlays and cloud-init ISOs.')

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
        booleanParam(name: 'AUTO_APPROVE', defaultValue: true,
               description: 'Skip the interactive plan confirmation for apply/destroy.')

        booleanParam(name: 'PLAN_WITH_DETAILS', defaultValue: false,
               description: 'Show a detailed plan (-out + `terraform show`).')
    }

    environment {
        TF_IN_AUTOMATION = 'true'
        TF_INPUT         = '0'
        PROJECT          = "${params.PROJECT_NAME}"
        WORKDIR          = "${env.WORKSPACE}"
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

        stage('Prepare tfvars') {
            steps {
                script {
                    // Generate a terraform.tfvars from the pipeline parameters.
                    // The heredoc keeps Terraform interpolation out of Groovy by
                    // using a quoted delimiter and explicit string joins.
                    def tfvars = [
                        "project_name     = \"${params.PROJECT_NAME}\"",
                        "libvirt_uri      = \"${params.LIBVIRT_URI}\"",
                        "pool_name        = \"${params.POOL_NAME}\"",
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

        stage('Terraform apply') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                script {
                    def args = params.AUTO_APPROVE ? '-auto-approve' : ''
                    sh "terraform apply -input=false ${args} -lock=false"
                }
            }
        }

        stage('Terraform destroy') {
            when { expression { params.ACTION == 'destroy' } }
            steps {
                script {
                    def args = params.AUTO_APPROVE ? '-auto-approve' : ''
                    sh "terraform destroy -input=false ${args} -lock=false"
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
    }

    post {
        always {
            sh 'terraform output -json > tf_outputs.json 2>/dev/null || true'
            // NOTE: keep the workspace. terraform.tfstate lives here and deleting
            // the workspace would orphan every VM/network the pipeline created.
            // For a shared/robust setup, configure a remote backend instead
            // (see README) and then you may safely enable cleanWs().
            archiveArtifacts artifacts: 'tf_outputs.json, ssh_commands.txt, terraform.tfstate*, .terraform.lock.hcl', allowEmptyArchive: true
        }
        success {
            echo 'Pipeline finished successfully.'
        }
        failure {
            echo 'Pipeline FAILED.'
        }
    }
}
