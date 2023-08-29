import boto3
import os

def handler(event, context):
    ec2 = boto3.resource('ec2')
    
    print(f"Received event: {event}")
    
    # Get details of the unhealthy instance
    instance_id = event['detail']['instance-id']
    instance = ec2.Instance(instance_id)
    
    print(f"Retrieving IAM instance profile for instance: {instance_id}")
    # Retrieve IAM instance profile ARN of the terminated instance
    iam_instance_profile_arn = None
    if instance.iam_instance_profile:
        iam_instance_profile_arn = instance.iam_instance_profile['Arn']
        print(f"Found IAM instance profile ARN: {iam_instance_profile_arn}")
    else:
        print(f"No IAM instance profile associated with instance: {instance_id}")

    print(f"Terminating instance: {instance_id}")
    # Terminate the unhealthy instance
    instance.terminate()
    
    print(f"Fetching user data from EFS for domain: {event['domain']}")
    # Fetch the user data from EFS
    user_data = read_user_data_from_efs(event['efs_file_system'], event['domain'])
    
    print(f"Launching a new EC2 instance with fetched user data")
    # Launch a new instance with fetched user data
    new_instance = ec2.create_instances(
        ImageId=os.environ['ami_id'],
        InstanceType=os.environ['instance_type'],
        KeyName=os.environ['key_name'],
        UserData=user_data,  # Use the fetched user data
        SecurityGroupIds=[event['security_group_id']],
        IamInstanceProfile={
            'Arn': iam_instance_profile_arn
        },
        MinCount=1,
        MaxCount=1
    )[0]
    
    print(f"New instance {new_instance.id} launched successfully")
    
    # Get the EIP associated with the terminated instance
    eips = boto3.client('ec2').describe_addresses(PublicIps=[instance.public_ip_address])
    if eips and 'Addresses' in eips and len(eips['Addresses']) > 0:
        eip = eips['Addresses'][0]
        print(f"Disassociating EIP {eip['PublicIp']} from terminated instance")
        # Disassociate EIP from terminated instance
        boto3.client('ec2').disassociate_address(PublicIp=eip['PublicIp'])
        
        print(f"Associating EIP {eip['PublicIp']} with new instance {new_instance.id}")
        # Associate the new instance with the EIP
        boto3.client('ec2').associate_address(InstanceId=new_instance.id, PublicIp=eip['PublicIp'])

    return {
        'statusCode': 200,
        'body': f"Replaced instance {instance_id} with {new_instance.id} and associated with EIP {eip['PublicIp']}"
    }

def read_user_data_from_efs(efs_file_system, domain):
    # Construct the full EFS file path
    efs_file_path = f"/mnt/efs/{domain}.sh"
    
    try:
        print(f"Reading content from EFS file path: {efs_file_path}")
        # Read the content of the file
        with open(efs_file_path, 'r') as file:
            user_data_content = file.read()
        
        print(f"Successfully fetched user data from EFS for domain: {domain}")
        return user_data_content
    
    except Exception as e:
        print(f"Error fetching user data from EFS: {e}")
        return None
