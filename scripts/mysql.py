#!/usr/bin/python
import sqlalchemy
import socket
import queue



engine = create_engine("sqlite:///:memory:", echo=True)

base = declarative_base()

class Catchall(base):
    __tablename__ = "trashbin"

    id = Column(Integer,AUTOINCREMENT,primary_key=True)
    text = Column(string)

#Create the above table
base.metadata.create_all(engine)

#IP Socket info
port = 1234
ip = "127.0.0.2"
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((ip, port))


#Python Queue
q = Queue()

#Where the real work is done
while True:
    data, addr = sock.recvfrom(1024)
    print "Got: ", data
    q.put(data)

def worker():
    while True:
        item = q.get()
        work = Catchall(item)
        session.add(work)
        q.task_done()