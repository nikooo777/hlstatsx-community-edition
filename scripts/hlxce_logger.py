import logging
import datetime
import os
from sys import exit
import ConfigParser

#Create a golbal object for current time stamp
current_date = datetime.datetime.now()


def checks():
	#Check to see if the log folder exists
	if os.path.exists("./logs") == FALSE:
		print ("Warning the log folder does not exist")
		if not os.makedirs("./logs"):
			print ("Error: Could not automaticly create logs folder please do so and rerun")
			sys.exit()
	else:

def init_log():
	#Set up logging handles
	db_logs = logger.getLogger("Database")
	damon_logs = logger.getLogger("Daemon")
	misc_logs = logger.getLogger("Misc")

	#Set up logging file handles
	db_log_file = logging.FileHandler("./logs/Database.log")
	daemon_log_file = logging.FileHandler("./logs/Daemon.log")
	misc_log_file = logging.FileHandler("./logs/Misc.log")

	#Read the config file to set up custom formats
	log_settings = ConfigParser.ConfigParser()
	log_format = logging.Formatter(log_settings.get("Logging","Format"))

	#Set the log format from the config file
	db_log_file.setFormatter(log_format)
	daemon_logs.setFormatter(log_format)
	misc_logs.setFormatter(log_format)

def log_write(location,msg):
	if location.lowercase == "database":
		use db_log_file
	elif location.lowercase == "daemon":
		use daemon_log_file
	else:
		use misc_logs


if __name__ == "__main__":
	checks()
	cycle_logs(date)
	init_log()