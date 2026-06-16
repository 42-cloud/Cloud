from diagrams import Diagram, Cluster, Edge
from diagrams.custom import Custom
from diagrams.generic.network import Firewall
from diagrams.generic.storage import Storage

from diagrams.aws.network import InternetGateway
from diagrams.aws.network import RouteTable

from diagrams.aws.security import IdentityAndAccessManagementIamRole as IAMRole
from diagrams.aws.security import KMS
from diagrams.aws.security import WAF as SG

from diagrams.aws.compute import EC2Instance
from diagrams.aws.compute import EC2ElasticIpAddress
from diagrams.aws.management import Cloudwatch
from diagrams.aws.management import ManagementConsole

graph_attr = {
    "splines": "spline",
    "fontsize": "12"
}

with Diagram("Cloud architecture", outformat='png', show=False, graph_attr=graph_attr):

    with Cluster("IaC tools"):
        terraform = Custom("Terraform", "./terraform.png")
        ansible = Custom("Ansible", "./ansible.png")
        duckDNS = Custom("DuckDNS", "./duckdns.png")
        ini_file = Storage("inventory.ini\n(2 groupes : angie_lb / backends)")

    aws_api = ManagementConsole("AWS API")
    repository = Storage("repository\n(apt update)")

    with Cluster("AWS observability"):
        cloudwatch = Cloudwatch("VPC flow logs")
        flowlog_role = IAMRole("flowlog-role\n(= instance profile EC2)")
        kms_keys = KMS("KMS key\n(chiffrement log group)")

    with Cluster("AWS VPC (10.0.0.0/16)"):
        default_sg = SG("default SG\n(restricted, inutilisé)")

        with Cluster("Public Subnet (10.0.1.0/24)"):
            igw = InternetGateway("Internet Gateway")
            rt_lb = RouteTable("RT lb\n0.0.0.0/0 -> igw")
            eip = EC2ElasticIpAddress("EIP")
            sg_lb = SG("SG angie_lb\n22/80/443 in")
            ec2_lb = EC2Instance("EC2 Angie LB\n(reverse proxy + NAT instance)")

        with Cluster("Backend Subnet (10.0.2.0/24)"):
            rt_backends = RouteTable("RT backends\n0.0.0.0/0 -> ENI(ec2_lb)")
            sg_backends = SG("SG backends\n80/22 depuis sg_lb uniquement")
            with Cluster("Backend instances (for_each)"):
                ec2_b1 = EC2Instance("backend-1")
                ec2_b2 = EC2Instance("backend-2")

    # --- Provisioning IaC ---
    terraform >> Edge(color="blue", label="1. apply", style="bold") >> aws_api
    aws_api >> Edge(color="blue", style="dashed") >> ec2_lb
    aws_api >> Edge(color="blue", style="dashed") >> [ec2_b1, ec2_b2]
    aws_api >> Edge(color="blue", style="dashed") >> eip

    eip >> Edge(color="darkgreen", label="2. expose IP", style="dashed") >> terraform
    terraform >> Edge(color="darkgreen", label="3. generate") >> ini_file
    ansible << Edge(color="orange", label="4. read IP + cfg ProxyJump") << ini_file

    ansible >> Edge(label="5. configure (SSH direct)", style="dashed", color="blue") >> ec2_lb
    ansible >> Edge(label="5b. configure (SSH via ProxyJump)", style="dashed", color="blue") >> [ec2_b1, ec2_b2]

    # --- Observability ---
    [ec2_lb, ec2_b1, ec2_b2] >> Edge(style="dotted") >> cloudwatch
    flowlog_role >> Edge(style="dotted") >> cloudwatch
    flowlog_role >> Edge(style="dotted", label="instance profile") >> [ec2_lb, ec2_b1, ec2_b2]
    kms_keys >> Edge(style="dotted") >> cloudwatch

    # --- DNS (NB: liaison sous-domaine <-> EIP pas encore automatisée) ---
    duckDNS >> Edge(color="red", label="résolution domaine\n(à automatiser)", style="dashed") >> eip

    # --- Trafic web entrant : Internet -> IGW -> SG lb -> Angie -> SG backends -> backend ---
    eip >> Edge(color="red") >> igw >> Edge(color="red") >> sg_lb >> Edge(color="red") >> ec2_lb
    ec2_lb >> Edge(color="red", label="proxy_pass :80") >> sg_backends >> Edge(color="red") >> [ec2_b1, ec2_b2]

    # --- Trafic sortant Angie LB (updates / repo) ---
    ec2_lb >> Edge(color="blue") >> rt_lb >> Edge(color="blue") >> igw >> Edge(color="blue") >> repository

    # --- Trafic sortant backends : pas de NAT Gateway, NAT via l'instance Angie ---
    [ec2_b1, ec2_b2] >> Edge(color="purple", label="NAT via ec2_lb\n(source_dest_check=false)") >> rt_backends >> Edge(color="purple") >> ec2_lb