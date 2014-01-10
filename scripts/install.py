import ConfigParser
import os
import socket
import logging
import gettext

#We want to start the log process before anything else is done
log = logging.getLogger('Installer')
logFile = logging.FileHandler('./logs/installer.log')
format = logging.Formatter('%(asctime)s %(levelname)s %(message)s')
logFile.setFormatter(format)
log.addHandler(logFile)
log.setLevel(logging.DEBUG)


#Set path and default language


#Grabs the base ip for the system
ip = str([ip for ip in socket.gethostbyname_ex(socket.gethostname())[2] if not ip.startswith("127.")][:1])

user_ip = raw_input("Please enter a ip for the deamon to listen on %s:"%ip)
if user_ip == "":
	log.debug("default input")
	user_ip = str(ip).strip("[]")
elif user_ip.lower() == "any":
	log.debug ("BindIP == all")
	user_ip = "*"
else:
	log.debug(user_ip)

config = ConfigParser.ConfigParser()
config.add_section("Database")
config.add_section("Daemon")
config.add_section("Logging")
config.set("Database", "Host", "127.0.0.1")
config.set("Database", "User", "root")
config.set("Database", "Password", "")
config.set("Database", "Socket", "")
config.set("Database", "Database", "")
config.set("Daemon", "BindIP", "%s"%user_ip)
config.set("Daemon", "Port", "27500:27500")
config.set("Logging", "Level", "Debug")


# Writing our configuration file to "example.cfg"
with open("./config/hlx.cfg", "w") as configfile:
    config.write(configfile)
