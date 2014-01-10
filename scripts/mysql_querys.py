#!/usr/bin/python
import mysql


#Creation of Cursor for Query
the_database_connection = mysql.connect()
cursor = the_database_connection.cursor()

#SteamID Temp Query
#Not sure if we need to create multiple functions for each query or not
def steam_temp_query1():

    cursor.execute ("SELECT SteamID FROM pythondb")
    row = cursor.fetchone()

    print "Steam User:", row[0]

    print "Query Successful"

#Name Temp Query
def steam_temp_query2():
    cursor.execute ("SELECT Name FROM pythondb")
    row1 = cursor.fetchone()

    print "Name:", row1[0]
    print "Query Successful"

if __name__ == "__main__":
    #Allows for return of query information
    #Then prints information to Daemon
    
    steam_id = steam_temp_query1()
    print(steam_id)
    steam_name = steam_temp_query2()
    print (steam_name)
