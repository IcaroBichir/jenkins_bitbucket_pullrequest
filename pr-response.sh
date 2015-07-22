#!/bin/bash

function execute_build() {
	COMMIT=${1}
	REPO=${2}
	USERNAME_JENKINS=${3}
	PASSWORD_JENKINS=${4}
	JOB_NAME=${5}
	BUILD_NUMBER=${6}
	USERNAME_BITBUCKET=${7}
	PASSWORD_BITBUCKET=${8}
	BUCKET_API_V1_URL=${9}
	OWNER=${10}
	PULL_REQUEST=${11}
	BUILD_URL=${12}
	JENKINS_URL=${13}

	echo "build will be executed..."
	git checkout "$COMMIT"
	echo "executing ci.sh..."
	sleep 5
	cd $REPO
	./ci.sh
	if [ $? -eq 0 ]; then
		JENKINS_RESULT="SUCCESS"
	else 
		JENKINS_RESULT="FAILED"
	fi		
	collect_coverage_percentage
    language_comment
    echo -e "bitbucket comment registered"
} 

function collect_state() {
	PRSTATE=`curl --silent -u ${USERNAME_BITBUCKET}:${PASSWORD_BITBUCKET} https://${BUCKET_API_V2_URL}/${OWNER}/${REPO}/pullrequests?state=open | python -mjson.tool | jq '.values[] | select(.state == "OPEN") | .state' | sed 's/"//g'`
}

function collect_comment() {
	COMMENT=`curl --silent -u ${USERNAME_BITBUCKET}:${PASSWORD_BITBUCKET} https://${BUCKET_API_V2_URL}/${OWNER}/${REPO}/pullrequests/${PULL_REQUEST}/comments | python -mjson.tool | jq '.values[] | .content | .raw' | sed 's/"//g' | egrep -m 1 -e 'SUCCESS|FAILED'`
}

function content_comment() {
	CONTENT_COMMENT=`curl --silent -u ${USERNAME_BITBUCKET}:${PASSWORD_BITBUCKET} https://${BUCKET_API_V2_URL}/${OWNER}/${REPO}/pullrequests/${PULL_REQUEST}/comments | python -mjson.tool | jq '.values[] | .content | .raw' | sed 's/"//g'`
}

function post_comment() {
	curl --silent -u ${USERNAME_BITBUCKET}:${PASSWORD_BITBUCKET} https://${BUCKET_API_V1_URL}/${OWNER}/${REPO}/pullrequests/${PULL_REQUEST}/comments --data "content=${1}"
}

function check_null_percentage() {
	if [ "${PERCENTAGE}" == " %" ]; then
		PERCENTAGE=''
	fi
}

function collect_coverage_percentage() {
	case ${LANGUAGE} in
		python)
			collect_python_coverage_percentage
			;;
		ruby)
			collect_ruby_coverage_percentage
			;;
		*)
			collect_unknown_language_coverage_percentage
			;;
	esac
}

function collect_python_coverage_percentage() {
	TEMP=`curl --silent http://${USERNAME_JENKINS}:${PASSWORD_JENKINS}@${JENKINS_URL}/job/${JOB_NAME}/ws/${REPO}/coverage.xml | grep -m 1 line-rate | awk '{ print $3 }' | sed 's/.*line-rate="\(.*\)".*/\1/'`
	PERCENTAGE=" `echo "scale=2; $TEMP*100" | bc | cut -c1-5`%"
	check_null_percentage
}

function collect_ruby_coverage_percentage() {
	PERCENTAGE=" `curl --silent http://${USERNAME_JENKINS}:${PASSWORD_JENKINS}@${JENKINS_URL}/job/${JOB_NAME}/ws/${REPO}/coverage/.last_run.json | python -mjson.tool | grep -m 2 covered_percent | awk '{ print $2 }'`%"
	check_null_percentage
}

function collect_unknown_language_coverage_percentage() {
	PERCENTAGE="Warning: Unknown Language. Could not get Code Coverage."
}

function language_comment() {
         case ${LANGUAGE} in
                python)
                        language_python_comment
                        ;;
                ruby)
                        language_ruby_comment
                        ;;
                *)
                        comment_unknown_language
                        ;;
        esac
}

function language_python_comment() {
  if [ "$JENKINS_RESULT" == 'SUCCESS' ]; then
	post_comment "SUCCESS on commit: ${COMMIT}. [Console Output](${BUILD_URL}console). [Code Coverage](http://${JENKINS_URL}/job/${JOB_NAME}/ws/${REPO}/htmlcov/index.html)${PERCENTAGE}. [Violations](http://${JENKINS_URL}/job/${JOB_NAME}/violations/)"
  else
	post_comment "FAILED on commit: ${COMMIT}. [Console Output](${BUILD_URL}console). [Code Coverage](http://${JENKINS_URL}/job/${JOB_NAME}/ws/${REPO}/htmlcov/index.html)${PERCENTAGE}. [Violations](http://${JENKINS_URL}/job/${JOB_NAME}/violations/)"
  fi
}

function language_python_comment() {
  if [ "$JENKINS_RESULT" == 'SUCCESS' ]; then
    post_comment "SUCCESS on commit: ${COMMIT}. [Console Output](${BUILD_URL}console). [Code Coverage](http://${JENKINS_URL}/job/${JOB_NAME}/ws/${REPO}/coverage/index.html)${PERCENTAGE}. [Violations](http://${JENKINS_URL}/job/${JOB_NAME}/violations/)"
  else
    post_comment "FAILED on commit: ${COMMIT}. [Console Output](${BUILD_URL}console). [Code Coverage](http://${JENKINS_URL}/job/${JOB_NAME}/ws/${REPO}/coverage/index.html)${PERCENTAGE}. [Violations](http://${JENKINS_URL}/job/${JOB_NAME}/violations/)"
  fi
}

function comment_unknown_language() {
  echo "Unknown Language"
}

if [ ! -d "${REPO}" ]; then
	git clone git@bitbucket.org:${OWNER}/${REPO}.git 
fi

cd ${REPO}
git fetch origin

collect_state
if [[ "${PRSTATE}" =~ ^OPEN.*$ ]]; then
	curl --silent -u ${USERNAME_BITBUCKET}:${PASSWORD_BITBUCKET} https://${BUCKET_API_V2_URL}/${OWNER}/${REPO}/pullrequests?state=open | python -mjson.tool | jq '.values[] | select(.state == "OPEN") | .id' | while read PULL_REQUEST; do
		collect_comment
		curl --silent -u ${USERNAME_BITBUCKET}:${PASSWORD_BITBUCKET} https://${BUCKET_API_V2_URL}/${OWNER}/${REPO}/pullrequests/${PULL_REQUEST} | python -mjson.tool | jq '.source[] | .hash' | grep -v null | sed 's/"//g' | while read COMMIT; do 
			if [[ ! -z "${COMMENT}" ]] && [[ ! "${COMMENT}" =~ "SUCCESS|FAILED" ]]; then
				content_comment
				if [[ "${CONTENT_COMMENT}" == *"${COMMIT}"* ]]; then
					echo "Jenkins already evaluated this Pull Request"
				else
					execute_build "${COMMIT}" "${REPO}" "${USERNAME_JENKINS}" "${PASSWORD_JENKINS}" "${JOB_NAME}" "${BUILD_NUMBER}" "${USERNAME_BITBUCKET}" "${PASSWORD_BITBUCKET}" "${BUCKET_API_V1_URL}" "${OWNER}" "${PULL_REQUEST}" "${BUILD_URL}"
				fi
			else
				execute_build "${COMMIT}" "${REPO}" "${USERNAME_JENKINS}" "${PASSWORD_JENKINS}" "${JOB_NAME}" "${BUILD_NUMBER}" "${USERNAME_BITBUCKET}" "${PASSWORD_BITBUCKET}" "${BUCKET_API_V1_URL}" "${OWNER}" "${PULL_REQUEST}" "${BUILD_URL}"
			fi
		done
	done
else
	echo "There is no open Pull Request"
	exit 0
fi
