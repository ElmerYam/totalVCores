#!/usr/bin/env bash


usage() {

	echo "Script to retrieve the total vCores in use by RTF environments"
	echo
	echo "Usage: totalVCores.sh <TOKEN> <ENV>"
	echo " <TOKEN> - token retrieved after 2-factor authentication with Anypoint"
	echo " <ENV>   - name of the environment to retrieve total the vCores from (matches exactly)"
	echo
	echo "Options:"
	echo " -h - print this help"
	echo " -o - specify the name of the organization to use (matches exactly)"
	echo " -t - specify the type of the environment"
	echo " -e - specify the environment name"
}

isRTF() {
	local TOKEN=$1
	local ORG_ID=$2
	IS_RTF=$(curl -sSL -X GET -H "Authorization: Bearer $TOKEN" https://anypoint.mulesoft.com/runtimefabric/api/organizations/$ORG_ID/fabrics | jq '. | length > 0')
	[[ ${IS_RTF} = true ]]
}

isCH2() {
	local TOKEN=$1
	local ORG_ID=$2
	IS_CH2=$(curl -sSL -X GET -H "Authorization: Bearer $TOKEN" https://anypoint.mulesoft.com/runtimefabric/api/organizations/$ORG_ID/privatespaces | jq '.content | length > 0')
	[[ ${IS_CH2} = true ]]
}

# Verify required applications are installed
if ! command -v jq &> /dev/null
then
	echo "This script uses jq to parse JSON, please install it and then rerun the script"
	echo "jq website: https://jqlang.github.io/jq/"
	exit 1
fi

if ! command -v curl $> /dev/null
then
	echo "This script uses curl to make HTTP calls, please install it and then rerun the script"
	exit 1
fi

# Parse Options
while getopts ":o:e:t:h" options; do
	case "${options}" in
		o)
			ORG_NAME=${OPTARG}
			;;
		e)
			ENV_NAME=${OPTARG}
			echo "-e opt  - ${OPTARG}"
			;;
		t)
			ENV_TYPE=${OPTARG}
			echo "-t opt - ${OPTARG}"
			;;
		:)
			echo "Option -${OPTARG} requires an argument."
      		exit 1
      		;;
		h)
			usage
			exit 0
			;;
		*)
			usage
			exit 1
			;;
	esac
done
shift "$((OPTIND-1))"

# Verify Input
[[ -z "$1" ]] && echo "No TOKEN provided" && usage && exit 1
[[ -z "$2" ]] && echo "No ENV provided" && usage && exit 1

# Extract Input
TOKEN=$1
ENV=$2

echo "TOKEN = $TOKEN"
echo "ENV = $ENV"

# Set up variables
CH2_TOTAL=0
RTF_TOTAL=0
CH1_TOTAL=0

# Get Org ID
if [[ -z "${ORG_NAME}" ]]
then
	ORG_ID=$(curl -sSL -X GET -H "Authorization: Bearer $TOKEN" https://anypoint.mulesoft.com/accounts/api/me | jq -r '.user.organization.id')
	echo "Organization ID: ${ORG_ID}"
else
	ORG_ID=$(curl -sSL -X GET -H "Authorization: Bearer $TOKEN" https://anypoint.mulesoft.com/accounts/api/me | jq -r --arg name "$ORG_NAME" '.user.memberOfOrganizations[] | select(.name==($name)) | .id')
	echo "${ORG_NAME} Organization ID: ${ORG_ID}"
fi

# Get Environment IDs
ENV_ID=$(curl -sSL -X GET -H "Authorization: Bearer $TOKEN" https://anypoint.mulesoft.com/accounts/api/organizations/$ORG_ID/environments | jq -r --arg env $ENV '.data[] | select (.name==($env)) | .id')

if [[ -z ${ENV_ID} ]]
then
	echo -e "${ENV} environment was not found - it must match exactly.\nAvailable Environments:"
	curl -sSL -X GET -H "Authorization: Bearer $TOKEN" https://anypoint.mulesoft.com/accounts/api/organizations/$ORG_ID/environments | jq -r --arg env $ENV '.data[].name'
	exit 1
else
	echo "${ENV} Environment ID: ${ENV_ID}"
fi


#############
# Check CH2 #
#############
if isCH2 ${TOKEN} ${ORG_ID}
then
	echo -e "\n\nApps Deployed to CloudHub 2.0:\n------------------------------"
	
	APPS=$(curl -sSL -X GET -H "Authorization: Bearer $TOKEN" https://anypoint.mulesoft.com/hybrid/api/v2/organizations/$ORG_ID/environments/$ENV_ID/deployments | jq -c '.items[] | select(.application.status=="RUNNING") | {name, id}')

	# Get Deployment Details
	for APP in $APPS
	do
		NAME=$(echo $APP | jq -r '.name')
		ID=$(echo $APP | jq -r '.id')
		DETAILS=$(curl -sSL -X GET -H "Authorization: Bearer $TOKEN" https://anypoint.mulesoft.com/hybrid/api/v2/organizations/$ORG_ID/environments/$ENV_ID/deployments/$ID | jq -r "{vCores: .application.vCores,replicas: .target.replicas}")
		VCORES=$(echo $DETAILS | jq -r '.vCores')
		REPLICAS=$(echo $DETAILS | jq -r '.replicas')
		APP_TOTAL=`bc <<< "scale=2; ${VCORES} * ${REPLICAS}"`
		CH2_TOTAL=`bc <<< "scale=1; ${CH2_TOTAL} + ${APP_TOTAL}"`
		echo -e "${NAME}\n  ID: ${ID}\n  vCores: ${VCORES}\n  Replicas: ${REPLICAS}\n  App Total: ${APP_TOTAL}"
	done
	
	echo -e "\n\nCloudhub 2.0 App Total vCPU: ${CH2_TOTAL} vCores"
fi

############
# RTF Apps #
############
if isRTF ${TOKEN} ${ORG_ID}
then
	echo -e "\n\nRTF Applications:\n-----------------"

	# Get All Deployments
	APPS=$(curl -sSL -X GET -H "Authorization: Bearer $TOKEN" https://anypoint.mulesoft.com/hybrid/api/v2/organizations/$ORG_ID/environments/$ENV_ID/deployments | jq -c '.items[] | select(.application.status=="RUNNING") | {name, id}')

	# Get Deployment Details
	for APP in $APPS
	do
		NAME=$(echo $APP | jq -r '.name')
		ID=$(echo $APP | jq -r '.id')
		DETAILS=$(curl -sSL -X GET -H "Authorization: Bearer $TOKEN" https://anypoint.mulesoft.com/hybrid/api/v2/organizations/$ORG_ID/environments/$ENV_ID/deployments/$ID | jq -r "{mCPU: .target.deploymentSettings.resources.cpu.limit,replicas: .target.replicas}")
		MCPU=$(echo $DETAILS | jq -r '.mCPU' | tr -d -c 0-9)
		VCORES=`bc <<< "scale=2; ${MCPU} / 1000"`
		REPLICAS=$(echo $DETAILS | jq -r '.replicas')
		APP_TOTAL=`bc <<< "scale=2; ${VCORES} * ${REPLICAS}"`
		RTF_TOTAL=`bc <<< "scale=1; ${RTF_TOTAL} + ${APP_TOTAL}"`
		echo -e "${NAME}\n  ID: ${ID}\n  millicpu: ${MCPU}\n  vCPU: ${VCORES}\n  Replicas: ${REPLICAS}\n  App Total: ${APP_TOTAL}"
	done

	echo -e "\n\nRTF App Total vCPU: ${RTF_TOTAL} vCores"
fi

#################
# Cloudhub Apps #
#################

RESULT=$(curl -sSL -X GET -H "Authorization: Bearer $TOKEN" -H "X-ANYPNT-ENV-ID: $ENV_ID" https://anypoint.mulesoft.com/cloudhub/api/v2/applications)

if [ $(echo ${RESULT} | jq '. | length > 0') = true ]
then
	echo -e "\n\nCloudhub 1.0 Applications:\n--------------------------"
	
	APPS=$(echo ${RESULT} | jq -c 'map({domain,status,workerSize: .workers.type.weight,workerCount: .workers.amount}) | .[] | select(.status=="STARTED")') 

	for APP in $APPS
	do
		NAME=$(echo $APP | jq -r '.domain')
		WORKER_SIZE=$(echo $APP | jq -r '.workerSize')
		WORKER_COUNT=$(echo $APP | jq -r '.workerCount')
		APP_VCPU=`bc <<< "scale=0; ${WORKER_SIZE} * ${WORKER_COUNT}"`
		CH1_TOTAL=`bc <<< "scale=2; $CH1_TOTAL + $APP_VCPU"` # Add value to total
		echo -e "${NAME}\n  Worker Size: ${WORKER_SIZE}\n  Worker Count: ${WORKER_COUNT}\n  App Total: ${APP_VCPU}"
	done

	echo -e "\n\nCloudhub 1.0 App Total vCPU: ${CH1_TOTAL} vCores"

fi
# Divide to get vCPU limit total
TOTAL=`bc <<< "scale=3; ${CH2_TOTAL} + ${RTF_TOTAL} + ${CH1_TOTAL}"`

echo -e "\n\nTotal vCPU license consumed in ${ENV}: ${TOTAL}"
