from diagrams import Diagram, Cluster, Edge
from diagrams.custom import Custom
from diagrams.generic.network import Firewall
from diagrams.generic.storage import Storage

from diagrams.aws.network import VPC
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

with Diagram("Cloud architecture", outformat='png', show=False):

    with Cluster("IaC tools"):
        terraform = Custom("Terraform", "./terraform.png")
        ansible = Custom("Ansible", "./ansible.png")
        duckDNS = Custom("DuckDNS", "./duckdns.png")
        ini_file = Storage("hosts.ini\n(Généré par TF)")

    aws_api = ManagementConsole("AWS API")
    repository = Storage("repository")

    with Cluster("AWS observability"):
        cloudwatch = Cloudwatch("cloudwatch (logs)")
        generic_role = IAMRole("generic IAM role")
        kms_keys = KMS("KMS key")

    with Cluster("AWS VPC (10.0.0.0/16)"):
        igw = InternetGateway("gateway")
        route_table = RouteTable("route table 0.0.0.0 -> gateway")
        with Cluster("Public Subnet (10.0.1.0/24)"):
            eip = EC2ElasticIpAddress("EIP")
            ec2 = EC2Instance("EC2 instance\nUbuntu")
            sg = Firewall("Security group\n22/80/443")

    # IaC
    terraform >> Edge(color="blue", label="1. apply", style="bold") >> aws_api
    aws_api >> Edge(color="blue", style="dashed") >> ec2
    aws_api >> Edge(color="blue", style="dashed") >> eip

    eip >> Edge(color="darkgreen", label="2. expose IP", style="dashed") >> terraform
    terraform >> Edge(color="darkgreen", label="3. generate") >> ini_file
    ansible << Edge(color="orange", label="4. read IP") << ini_file
    ansible >> Edge(label="5. configure", style="dashed", color="blue") >> igw >> route_table >> sg >> ec2

    # AWS
    ec2 >> cloudwatch
    generic_role >> Edge(style="dotted") >> ec2
    kms_keys >> Edge(style="dotted") >> ec2

    # network flow from web
    duckDNS >> Edge(color="red", label="domain name resolution") >> eip
    eip >> Edge(color="red") >> igw >> Edge(color="red") >> Edge(color="red") >> sg >> Edge(color="red") >> ec2

    # network flow to web (package update)
    ec2 >> Edge(color="blue") >> sg >> Edge(color="blue") >> route_table >> Edge(color="blue") >> igw >> Edge(color="blue") >> repository