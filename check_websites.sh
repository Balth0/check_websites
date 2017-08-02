#!/bin/bash
#
# -- check_websites.sh --
# 
# Description :
# -------------
# This script scan all containers exposed to the front-end looking for the url associated.
# Then, it check the service behind for a 200 http code.
# If not found, it restart the container and check again.
# if still KO, send a telegram notification with docker logs of the container.
#
# Works with :
# ------------
#  - Traefik
#  - nginx from jwilder
#  - custom label cw.check.url
#
# Prerequisites :
#   - Get telegram-notify.sh & telegram-notify.conf from Nicolas Bernaerts :
#      wget https://raw.githubusercontent.com/NicolasBernaerts/debian-scripts/master/telegram/telegram-notify-install.sh
#      wget https://raw.githubusercontent.com/NicolasBernaerts/debian-scripts/master/telegram/telegram-notify.conf
#   - Create a telegram bot :
#      Follow steps 1 to 13 here : https://github.com/topkecleon/telegram-bot-bash
#      /!\ Note down the API key given by @BotFather
#   - Get user ID :
#      + Send a message to your Bot from your Telegram client
#      + Call the following URL from any web browser. XXXXX = your API key.
#          https://api.telegram.org/botXXXXX/getUpdates
#          In the page displayed, you'll get some information. search for "from":"id":YYYYY, ". YYYYY is your user ID.
#   - Update telegram-notify.conf with your telegram API key and user ID.
# 
# Author :
#   Baltho ( cg.cpam@gmail.com )
#
# Versions :
#   - 2017-08-01: v1.1.1 :
#         - Get URL optimizations : no need to specify proxy's name. The script is 
#                             now looking first for custom label and next for traefik
#                             and nginx ones.
#         - Logs optimizations : Should be more efficient now.
#   - 2017-07-31: v1.1   :
#         - Custom URL test : If you have a url different from the base one to test,
#                             you can set a new label to your container :
#                             cw.check.url=sdom.domain.tld/location/file.ext
#         - Better log management : Only 1 only used when all checks are OK. 
#                             You cant see details of the last test on the .last file
#                             stored on the same location thant the log file.
#   - 2017-07-28: v1.0 - First release.

# Set the name of the docker's front-end network :
DOCKER_FRONTEND_NETWORK=traefik_proxy

# Path of the telegram-notify.sh script.
TELEGRAM_PATH=/data/scripts/telegram-notify.sh

# If a website is KO, do I restart the container ?
RESTART=yes

# LOGS_PATH = Path where logs will be stored
LOGS_PATH=/var/log
# LOG_FILE_NAME = Name of the log file
LOG_FILE_NAME=cw

# Temp file used to store current KO's containers name :
NOTIFIED_LIST=/tmp/notified

############################################################################################
# DOT NOT MODIFY ANYTHING BEHIND THIS LINE EXCEPT IF YOU KNOW EXACTLY WHAT YOU ARE DOING ! #
############################################################################################

DATE=$(date)
SCRIPT_LOG_FILE=$LOGS_PATH/$LOG_FILE_NAME.log
LOG_TEMP=$LOGS_PATH/$LOG_FILE_NAME.last

#--- Define text colors
CSI="\033["
CEND="${CSI}0m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"

#--- Set log header
echo " " > $LOG_TEMP
echo "+----------------+---------------+--------------+" >> $LOG_TEMP
echo "| $DATE" >> $LOG_TEMP
echo "|" >> $LOG_TEMP

# Check all running containers
for i in $(docker network inspect $DOCKER_FRONTEND_NETWORK | grep Name | sed 1d | awk -F\" '{print $4}')
 do
   # Get IP address and port from docker
   CONT_IP=$(docker inspect -f '{{ .NetworkSettings.Networks.$DOCKER_FRONTEND_NETWORK.IPAddress }}' $i)
   if [ -z "$CONT_IP" ]; then
     CONT_IP=$(docker inspect $i | grep VIRTUAL_PORT | awk -F"=" '{print $2}' | awk -F\" '{print $1}')
   fi
   CONT_PORT=$(docker inspect $i | grep traefik.backend.port | awk -F"\"" '{print $4}')
   DOCKER_SCRIPT_LOG_FILE=$LOGS_PATH/cw_$i.log
   
   if [ ! -z "$URL" ]; then
     # If there is a URL on that container, get http code associated
     RESULT=$(curl -s -o /dev/null -w "%{http_code}" -L $CONT_IP:CONT_PORT)
     if [ "$RESULT" != "200" ] && [ "RESTART" == "yes" ]; then
       # If website is KO, restart the container
       echo -e "[ ${CRED}KO$CEND ] ${CYELLOW}https://$URL$CEND down with code $RESULT. Try restarting container $i..." >> $LOG_TEMP
       docker restart $i >/dev/null
       sleep 10
       RESULT2=$(curl -s -o /dev/null -w "%{http_code}" -L $URL)
       # If website is still KO after a container restart, notify through telegram with container's logs
       if [ "$RESULT2" != "200" ]; then
         echo -e "[ ${CRED}ERR$CEND ] ${CYELLOW}https://$URL$CEND is still ${CRED}KO$CEND with http code : $RESULT2. Please check $i !" >> $LOG_TEMP
         if [ ! -f $NOTIFIED_LIST ] || [[ ! " $(cat $NOTIFIED_LIST) " =~ " $i " ]]; then
           docker logs $i > $DOCKER_SCRIPT_LOG_FILE 2>/dev/null
           $TELEGRAM_PATH --error --text "https://"$URL" is DOWN\nhttp code "$RESULT2"\nPlease check logs.\n "$i" restarted unsuccessfully." --document $DOCKER_SCRIPT_LOG_FILE
           echo $i >> $NOTIFIED_LIST
         fi
       else
         # If website if OK after a container's restart, notify it through telegram
         $TELEGRAM_PATH --success --text "https://"$URL" was KO, but is OK after $i's restart"
       fi
	 if [ "$RESULT" != "200" ] && [ "RESTART" == "no" ]; then
	   $TELEGRAM_PATH --error --text "https://"$URL" is DOWN\nhttp code "$RESULT2"\nPlease check logs." --document $DOCKER_SCRIPT_LOG_FILE
     elif [ "$RESULT" == "200" ]; then
       echo -e "[ ${CGREEN}OK$CEND ] https://$URL is up." >> $LOG_TEMP
       while read line; do
         if [ $line = "$i" ]; then
		   # If a previously KO website is now OK, notify it through telegram
           $TELEGRAM_PATH --success --text "https://"$URL" is back online"
           sed -i /$i/d $NOTIFIED_LIST
         fi
       done < $NOTIFIED_LIST
     fi
   fi
done

while read CHECK; do
  CHECK_KO=$(echo $CHECK | grep ERR)
  CHECK_STRING=${CHECK_KO/]/] $DATE : }
  if [ ! -z "$CHECK_KO" ]; then
    echo $CHECK_STRING >> $SCRIPT_LOG_FILE
    SITE_KO=1
  fi
done < /var/log/cw.last
if [ "$SITE_KO" != "1" ]; then
  echo -e "[ ${CGREEN}OK$CEND ] $DATE : All checks are OK" >> $SCRIPT_LOG_FILE
fi

if [ ! -s $NOTIFIED_LIST ]
then
  # If previously notified list is empty, remove file
  rm -f $NOTIFIED_LIST
fi 
