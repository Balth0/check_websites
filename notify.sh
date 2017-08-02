#!/bin/bash

function telegram() {
	# Function to send a message to a Telegram User or Channel.
	# Message is sent from a Telegram Bot and can contain icon, text, image and/or document.
	# Main parameters are :
	#   --text <text>       Text of the message or file holding the text
	#   --photo <file>      Image to display
	#   --document <file>   Document to transfer
	# Options are :
	#   --title <title>     Title of the message (if text message)
	#   --html              Use HTML mode for text content (markdown by default)
	#   --silent            Send message in silent mode (no user notification on the client)
	#   --user <user-id>    Recipient User or Channel ID (replaces user-id= in ${FILE_CONF})
	#   --key <api-key>     API Key of your Telegram bot (replaces api-key= in ${FILE_CONF})
	# Optionnal icons are :
	#   --success           Add a success icon
	#   --error             Add an error icon
	#   --question          Add a question mark icon
	#   --icon <code>       Add an icon by UTF code (ex 1F355)

	# initialise variables
	NOTIFY_TEXT=""
	DISPLAY_TEXT=""
	DISPLAY_PICT=""
	DISPLAY_ICON=""
	DISPLAY_MODE="markdown"
	DISPLAY_SILENT="false"

	# loop to retrieve arguments
	while test $# -gt 0
	do
	  case "$1" in
		"--text") shift; DISPLAY_TEXT="$1"; shift; ;;
		"--photo") shift; PICTURE="$1"; shift; ;;
		"--document") shift; DOCUMENT="$1"; shift; ;;
		"--title") shift; DISPLAY_TITLE="$1"; shift; ;;
		"--html") DISPLAY_MODE="html"; shift; ;;
		"--silent") DISPLAY_SILENT="true"; shift; ;;
		"--user") shift; TELEGRAM_USER_ID="$1"; shift; ;;
		"--key") shift; TELEGRAM_API_KEY="$1"; shift; ;;
		"--success") DISPLAY_ICON=$(echo -e "\U2705"); shift; ;;
		"--error") DISPLAY_ICON=$(echo -e "\U1F6A8"); shift; ;;
		"--question") DISPLAY_ICON=$(echo -e "\U2753"); shift; ;;
		"--icon") shift; DISPLAY_ICON=$(echo -e "\U$1"); shift; ;;
		*) shift; ;;
	  esac
	done
	
	# check API key and User ID
	[ "${TELEGRAM_API_KEY}" = "" ] && { echo "[Error] Please provide API key or set it in ${FILE_CONF}"; exit 1; }
	[ "${TELEGRAM_USER_ID}" = "" ] && { echo "[Error] Please provide User ID or set it in ${FILE_CONF}"; exit 1; }

	# -------------------------------------------------------
	#   Check for file existence
	# -------------------------------------------------------

	# if picture, check for image file
	[ "${PICTURE}" != "" -a ! -f "${PICTURE}" ] && { echo "[error] Image file ${PICTURE} doesn't exist"; exit; }

	# if document, check for document file
	[ "${DOCUMENT}" != "" -a ! -f "${DOCUMENT}" ] && { echo "[error] Document file ${DOCUMENT} doesn't exist"; exit; }

	# -------------------------------------------------------
	#   String preparation : space and line break
	# -------------------------------------------------------

	# if text is a file, get its content
	[ -f "${DISPLAY_TEXT}" ] && DISPLAY_TEXT="$(cat "${DISPLAY_TEXT}")"

	# convert \n to LF
	DISPLAY_TEXT="$(echo "${DISPLAY_TEXT}" | sed 's:\\n:\n:g')"

	# if icon defined, include ahead of notification
	[ "${DISPLAY_ICON}" != "" ] && NOTIFY_TEXT="${DISPLAY_ICON} "

	# if title defined, add it with line break
	if [ "${DISPLAY_TITLE}" != "" ]
	then
		# convert title according to Markdown or HTML
		[ "${DISPLAY_MODE}" = "html" ] && NOTIFY_TEXT="${NOTIFY_TEXT}<b>${DISPLAY_TITLE}</b>%0A%0A" \
						   || NOTIFY_TEXT="${NOTIFY_TEXT}*${DISPLAY_TITLE}*%0A%0A"
	fi

	# if text defined, replace \n by HTML line break
	[ "${DISPLAY_TEXT}" != "" ] && NOTIFY_TEXT="${NOTIFY_TEXT}${DISPLAY_TEXT}"

	# -------------------------------------------------------
	#   Notification
	# -------------------------------------------------------

	# if photo defined, display it with icon and caption
	if [ "${PICTURE}" != "" ]
	then
	  # display image
	  curl --silent --insecure --form chat_id=${TELEGRAM_USER_ID} --form disable_notification=${DISPLAY_SILENT} --form photo="@${PICTURE}" --form caption="${NOTIFY_TEXT}" "https://api.telegram.org/bot${TELEGRAM_API_KEY}/sendPhoto" 

	# if document defined, send it with icon and caption
	elif [ "${DOCUMENT}" != "" ]
	then
	  # transfer document
	  curl --silent --insecure --form chat_id=${TELEGRAM_USER_ID} --form disable_notification=${DISPLAY_SILENT} --form document="@${DOCUMENT}" --form caption="${NOTIFY_TEXT}" "https://api.telegram.org/bot${TELEGRAM_API_KEY}/sendDocument" 

	# else, if text is defined, display it with icon and title
	elif [ "${NOTIFY_TEXT}" != "" ]
	then
	  # display text message
	  curl --silent --insecure --data chat_id="${TELEGRAM_USER_ID}" --data "disable_notification=${DISPLAY_SILENT}" --data "parse_mode=${DISPLAY_MODE}" --data "text=${NOTIFY_TEXT}" "https://api.telegram.org/bot${TELEGRAM_API_KEY}/sendMessage"

	#  else, nothing, error
	else
	  # error message
	  echo "[Error] Nothing to notify"
	fi
}

function slack() {
 	content="\"attachments\": [ { \"mrkdwn_in\": [\"text\", \"fallback\"], \"fallback\": \"SSH login: $PAM_USER connected to \`$HOSTNAME\`\", \"text\": \"SSH login to \`$HOSTNAME\`\", \"fields\": [ { \"title\": \"User\", \"value\": \"$PAM_USER\", \"short\": true }, { \"title\": \"IP Address\", \"value\": \"$PAM_RHOST\", \"short\": true } ], \"color\": \"#F35A00\" } ]"
	curl -X POST --data-urlencode "payload={\"channel\": \"$SLACK_CHANNEL\", \"mrkdwn\": true, \"username\": \"ssh-bot\", $content, \"icon_emoji\": \":computer:\"}" $SLACK_WEBHOOK_URL &
}
