import sys, urllib.request, time

def check_ping(host):
    start = time.time()
    try:
        urllib.request.urlopen(f"http://{host}", timeout=3)
        return int((time.time() - start) * 1000)
    except:
        return -1

print("V2Ray/Xray Config Tester - MVP")
print("Provide host to test: python tester.py <host>")
if len(sys.argv) > 1:
    ping = check_ping(sys.argv[1])
    print(f"Ping for {sys.argv[1]}: {ping}ms" if ping != -1 else "Failed to connect")
