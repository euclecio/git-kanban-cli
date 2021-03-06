#!/bin/bash

source gkc-utils.sh

validCredentials

function getHelp {
    echo "Create a new Pull Request with the last commit
With no arguments nothing is asked.

    -h|--help       Show this help, then exit
    -c|--custom     The mode where everything is asked
    -t|--title      You can type title as an argument
    --not-ready     When PR still in progress, then don't add review stage label
\n"
}

custom=0
not_ready=0
title=""

args=("$@")
for i in "$@"
do
    if [[ "$i" = "-h" ]] || [[ "$i" = "--help" ]]; then
       printf "$(getHelp)"
       exit 0
    elif [[ "$i" = "-c" ]] || [[ "$i" = "--custom" ]]; then
        custom=1
    elif [[ "$i" = "-c" ]] || [[ "$i" = "--not-ready" ]]; then
        not_ready=1
    elif [[ "$i" = "-t" ]] || [[ "$i" = "--title" ]]; then
        title=$2
    elif [[ "$i" =~ ^- ]]; then
        echo "Invalid parameter: $i"
        exit 1
    fi
done

echo "Making a push of your local branch"
git push origin $(get_current_branch)

originBranch=$(get_current_branch)
destinationBranch="master"
issue_number=$(get_current_branch)

[[ $custom -eq 1 ]] && {
    printf "\n"
    read -p "This PR is related to which issue (Default: $(get_current_branch) | N for none): " issue_number_custom
}

[ ! -z "$issue_number_custom" ] && {
    issue_number=$issue_number_custom
}

issue_desc=""
[ ! -z "$issue_number" ] && [ "$issue_number" != "N" ] && {
    issue_desc="Connected to #$issue_number"

    issue_info=$(curl -s $COMMAND "$AUTHORIZATION" https://api.github.com/repos/"$REPO_PATH"/issues/"$issue_number")

    issue_exists=$(echo "$issue_info" | grep message)
    if [[ $issue_exists == *"Not Found"* ]]; then
        printf "\e[33mNo issue with this ID was found\e[0m\n"
        exit 1
    fi

    issue_in_progress=$(echo "$issue_info" | grep 'Stage: In progress')
    if [[ ! -z $issue_in_progress ]]; then
        gkc-issue-tag --change-stage 'In progress' 'Review' $issue_number
    fi
}

lastCommitMessage=$(git log --pretty=format:%s -n1)
[[ $custom -eq 1 ]] && {
    printf "\n"
    read -p "Type the title of your PR (Default: $lastCommitMessage): " title
}

[ -z "$title" ] && {
    title=$lastCommitMessage
}

addinfo=""
[[ $custom -eq 1 ]] && {
    printf "\n"
    read -p "Type any additional information (optional): " addinfo
}

[ $custom -eq 1 ] && {
    printf "\n"
    read -p "Type the stage of your PR (Default: Review): " stage
}

stageLabel="Stage: Review"
[ ! -z "$stage" ] && {
    stageLabel="Stage: $stage"
}

assignees=""
if [ ! -z ${GITHUB_USER+x} ]; then
    assignees=",\"assignees\": [\"$GITHUB_USER\"]"
fi

printf "\n"
# Creating a new pull request {{{
data="{\"title\": \"$title\",\"body\": \"$issue_desc \n\n$addinfo \n\n**Created by Git Kanban Cli**\",\"head\": \"$originBranch\",\"base\": \"$destinationBranch\" $assignees}"

request_return=$(curl -s -X POST -H "Content-Type: application/json" $COMMAND "$AUTHORIZATION" https://api.github.com/repos/"$REPO_PATH"/pulls -d "$data")

if [[ $request_return == *"Validation Failed"* ]]; then
    exit 1
fi

issue_pr_number=$(echo ${request_return} | python -m json.tool | grep number | head -n1 | sed 's/[^0-9]*//g')

[[ $not_ready -eq 0 ]] && {
    gkc-issue-tag --add "$stageLabel" $issue_pr_number
}
#}}}

echo "New Pull Request was created: "
urls=$(echo ${request_return} | python -m json.tool | sed -n -e '/"html_url":/ s/^.*"\(.*\)".*/\1/p')
pr_url=''
while read -r line; do
    if [[ "$line" == *"pull"* ]]; then
        pr_url="$line"
    fi
done <<< "$urls"
echo "$pr_url"

[ "$stageLabel" == "Stage: Review" ] && {
    author=$(cat /etc/passwd | grep 1000 | cut -d ':' -f1)
    "$CLIPP_PATH"/Cli/cpf-notify-slack "$author needs a review: ${pr_url[0]}" development
}

[ ! -z ${BROWSER+x} ] && {
    "$BROWSER" "${pr_url[0]}"
}
