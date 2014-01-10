import socket

port = 9667
ip = "192.168.1.8"

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

sock.bind((ip, port))

while True:
    data, addr = sock.recvfrom(1024)
    print "Got: ", data


def hlx_listner():
    while True:
        item = q.get()
        log_parse_socket(item)
        q.task_