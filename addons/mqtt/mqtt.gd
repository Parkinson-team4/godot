# MQTT client implementation in GDScript - Godot 4.x 최종 안정화 버전
# Loosely based on https://github.com/pycom/pycom-libraries/blob/master/lib/mqtt/mqtt.py
# Patched for Godot 4.x compatibility and Azure IoT Hub SSL requirements.
extends Node
@export var client_id = ""
@export var verbose_level = 2  # 0: quiet, 1: connections/subscriptions, 2: all messages
@export var binarymessages = false
@export var pinginterval = 30
@export var ca_cert_path = "res://certs/DigiCertGlobalRootG2.pem"  # Path to the new DigiCert Global Root G2 CA

var socket = null
var sslsocket = null
var websocket = null
var trusted_cert = null  # For storing the loaded CA certificate

const BCM_NOCONNECTION = 0
const BCM_WAITING_WEBSOCKET_CONNECTION = 1
const BCM_WAITING_SOCKET_CONNECTION = 2
const BCM_WAITING_SSL_SOCKET_CONNECTION = 3
const BCM_FAILED_CONNECTION = 5
const BCM_WAITING_CONNMESSAGE = 10
const BCM_WAITING_CONNACK = 19
const BCM_CONNECTED = 20

var brokerconnectmode = BCM_NOCONNECTION

var regexbrokerurl = RegEx.new()

const DEFAULTBROKERPORT_TCP = 1883
const DEFAULTBROKERPORT_SSL = 8883
const DEFAULTBROKERPORT_WS = 8080
const DEFAULTBROKERPORT_WSS = 8081

const CP_PINGREQ = 0xc0
const CP_PINGRESP = 0xd0
const CP_CONNACK = 0x20
const CP_CONNECT = 0x10
const CP_PUBLISH = 0x30
const CP_SUBSCRIBE = 0x82
const CP_UNSUBSCRIBE = 0xa2
const CP_PUBREC = 0x40
const CP_SUBACK = 0x90
const CP_UNSUBACK = 0xb0

var pid = 0
var user = null
var pswd = null
var keepalive = 120
var lw_topic = null
var lw_msg = null
var lw_qos = 0
var lw_retain = false

signal received_message(topic, message)
signal broker_connected()
signal broker_disconnected()
signal broker_connection_failed()

var receivedbuffer : PackedByteArray = PackedByteArray()

var common_name = null

func _ready():
	regexbrokerurl.compile('^(tcp://|wss://|ws://|ssl://)?([^:\\s]+)(:\\d+)?(/\\S*)?$')
	if client_id == "":
		client_id = "rr%d" % randi()

	if FileAccess.file_exists(ca_cert_path):
		var file = FileAccess.open(ca_cert_path, FileAccess.READ)
		var cert_data = file.get_as_text()
		file.close()
		trusted_cert = X509Certificate.new()
		var err = trusted_cert.load_from_string(cert_data)
		if err != OK:
			if verbose_level >= 1:
				print("ERROR: Failed to load CA certificate from %s, error=%d" % [ca_cert_path, err])
			trusted_cert = null
	else:
		if verbose_level >= 1:
			print("WARNING: CA certificate not found at %s" % ca_cert_path)

func senddata(data):
	var E = 0
	if sslsocket != null:
		E = sslsocket.put_data(data)
	elif socket != null:
		E = socket.put_data(data)
	elif websocket != null:
		E = websocket.put_packet(data)
	if E != 0:
		if verbose_level >= 1:
			print("ERROR: senddata failed, E=%d" % E)

func receiveintobuffer():
	if sslsocket != null:
		var sslsocketstatus = sslsocket.get_status()
		if sslsocketstatus == StreamPeerTLS.STATUS_CONNECTED or sslsocketstatus == StreamPeerTLS.STATUS_HANDSHAKING:
			sslsocket.poll()
			var n = sslsocket.get_available_bytes()
			if n > 0:
				var sv = sslsocket.get_data(n)
				if sv[0] == OK:
					receivedbuffer.append_array(sv[1])
				else:
					if verbose_level >= 1:
						print("ERROR: sslsocket.get_data failed, E=%d" % sv[0])

	elif socket != null and socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		socket.poll()
		var n = socket.get_available_bytes()
		if n > 0:
			var sv = socket.get_data(n)
			if sv[0] == OK:
				receivedbuffer.append_array(sv[1])
			else:
				if verbose_level >= 1:
					print("ERROR: socket.get_data failed, E=%d" % sv[0])

	elif websocket != null:
		websocket.poll()
		while websocket.get_available_packet_count() != 0:
			receivedbuffer.append_array(websocket.get_packet())

var pingticksnext0 = 0

func _process(delta):
	if brokerconnectmode == BCM_NOCONNECTION:
		pass
	elif brokerconnectmode == BCM_WAITING_WEBSOCKET_CONNECTION:
		websocket.poll()
		var websocketstate = websocket.get_ready_state()
		if websocketstate == WebSocketPeer.STATE_CLOSED:
			if verbose_level >= 1:
				print("WebSocket closed with code: %d, reason: %s" % [websocket.get_close_code(), websocket.get_close_reason()])
			brokerconnectmode = BCM_FAILED_CONNECTION
			emit_signal("broker_connection_failed")
		elif websocketstate == WebSocketPeer.STATE_OPEN:
			brokerconnectmode = BCM_WAITING_CONNMESSAGE
			if verbose_level >= 1:
				print("Websocket connection now open")

	elif brokerconnectmode == BCM_WAITING_SOCKET_CONNECTION:
		socket.poll()
		var socketstatus = socket.get_status()
		if socketstatus == StreamPeerTCP.STATUS_ERROR:
			if verbose_level >= 1:
				print("ERROR: TCP socket error")
			brokerconnectmode = BCM_FAILED_CONNECTION
			emit_signal("broker_connection_failed")
		if socketstatus == StreamPeerTCP.STATUS_CONNECTED:
			brokerconnectmode = BCM_WAITING_CONNMESSAGE

	elif brokerconnectmode == BCM_WAITING_SSL_SOCKET_CONNECTION:
		socket.poll()
		var socketstatus = socket.get_status()
		if socketstatus == StreamPeerTCP.STATUS_ERROR:
			if verbose_level >= 1:
				print("ERROR: TCP socket error before SSL")
			brokerconnectmode = BCM_FAILED_CONNECTION
			emit_signal("broker_connection_failed")
		if socketstatus == StreamPeerTCP.STATUS_CONNECTED:
			if sslsocket == null:
				sslsocket = StreamPeerTLS.new()
				var tls_options = TLSOptions.client(trusted_cert) if trusted_cert else null
				if verbose_level >= 1:
					print("Connecting socket to SSL with common_name=%s" % common_name)
				var E3 = sslsocket.connect_to_stream(socket, common_name, tls_options)
				if E3 != OK:
					if verbose_level >= 1:
						print("ERROR: sslsocket.connect_to_stream failed, E=%d" % E3)
					brokerconnectmode = BCM_FAILED_CONNECTION
					emit_signal("broker_connection_failed")
					sslsocket = null
			if sslsocket != null:
				sslsocket.poll()
				var sslsocketstatus = sslsocket.get_status()
				if sslsocketstatus == StreamPeerTLS.STATUS_CONNECTED:
					brokerconnectmode = BCM_WAITING_CONNMESSAGE
					if verbose_level >= 1:
						print("SSL connection established")
				elif sslsocketstatus >= StreamPeerTLS.STATUS_ERROR:
					if verbose_level >= 1:
						print("ERROR: SSL socket status error, status=%d" % sslsocketstatus)
					brokerconnectmode = BCM_FAILED_CONNECTION
					emit_signal("broker_connection_failed")
					sslsocket = null

	elif brokerconnectmode == BCM_WAITING_CONNMESSAGE:
		senddata(firstmessagetoserver())
		brokerconnectmode = BCM_WAITING_CONNACK

	elif brokerconnectmode == BCM_WAITING_CONNACK or brokerconnectmode == BCM_CONNECTED:
		receiveintobuffer()
		while wait_msg():
			pass
		if brokerconnectmode == BCM_CONNECTED and pingticksnext0 < Time.get_ticks_msec():
			pingreq()
			pingticksnext0 = Time.get_ticks_msec() + pinginterval*1000

	elif brokerconnectmode == BCM_FAILED_CONNECTION:
		cleanupsockets()

func set_last_will(stopic, smsg, retain=false, qos=0):
	assert((0 <= qos) and (qos <= 2))
	assert(stopic)
	self.lw_topic = stopic.to_utf8_buffer()
	self.lw_msg = smsg if binarymessages else smsg.to_utf8_buffer()
	self.lw_qos = qos
	self.lw_retain = retain
	if verbose_level >= 1:
		print("LASTWILL%s topic=%s msg=%s" % [" <retain>" if retain else "", stopic, smsg])

func set_user_pass(suser, spswd):
	if suser != null:
		self.user = suser.to_utf8_buffer()
		self.pswd = spswd.to_utf8_buffer()
	else:
		self.user = null
		self.pswd = null

static func encoderemaininglength(pkt, sz):
	assert(sz < 2097152)
	var i = 1
	while sz > 0x7f:
		pkt.resize(i + 1)
		pkt[i] = (sz & 0x7f) | 0x80
		sz >>= 7
		i += 1
	pkt.resize(i + 1)
	pkt[i] = sz

static func encodeshortint(pkt, n):
	assert(n >= 0 and n < 65536)
	pkt.append((n >> 8) & 0xFF)
	pkt.append(n & 0xFF)

static func encodevarstr(pkt, bs):
	encodeshortint(pkt, len(bs))
	pkt.append_array(bs)

func firstmessagetoserver():
	var clean_session = true
	var pkt = PackedByteArray([CP_CONNECT, 0x00])
	var sz = 10 + (2+len(self.client_id.to_utf8_buffer()))
	if self.user != null:
		sz += (2+len(self.user)+2+len(self.pswd))
	if self.lw_topic:
		sz += (2+len(self.lw_topic)+2+len(self.lw_msg))

	encoderemaininglength(pkt, sz)
	var remstartpos = len(pkt)
	encodevarstr(pkt, "MQTT".to_utf8_buffer())
	var protocollevel = 0x04
	var connectflags = (0xC0 if self.user != null else 0) | \
					   (0x20 if self.lw_retain else 0) | \
					   (self.lw_qos << 3) | \
					   (0x04 if self.lw_topic else 0) | \
					   (0x02 if clean_session else 0)
	pkt.append(protocollevel)
	pkt.append(connectflags)
	encodeshortint(pkt, self.keepalive)
	encodevarstr(pkt, self.client_id.to_utf8_buffer())
	if self.lw_topic:
		encodevarstr(pkt, self.lw_topic)
		encodevarstr(pkt, self.lw_msg)
	if self.user != null:
		encodevarstr(pkt, self.user)
		encodevarstr(pkt, self.pswd)
	assert(len(pkt) - remstartpos == sz)
	return pkt

func cleanupsockets(retval=false):
	if verbose_level >= 1:
		print("Cleaning up sockets")
	if socket:
		if sslsocket:
			sslsocket = null
		socket.disconnect_from_host()
		socket = null
	else:
		assert(sslsocket == null)

	if websocket:
		websocket.close()
		websocket = null
	brokerconnectmode = BCM_NOCONNECTION
	return retval

func connect_to_broker(brokerurl):
	assert(brokerconnectmode == BCM_NOCONNECTION)
	var brokermatch = regexbrokerurl.search(brokerurl)
	if brokermatch == null:
		if verbose_level >= 1:
			print("ERROR: Unrecognized brokerurl pattern: %s" % brokerurl)
		return cleanupsockets(false)
	var brokercomponents = brokermatch.strings
	var brokerprotocol = brokercomponents[1]
	var brokerserver = brokercomponents[2]
	var iswebsocket = (brokerprotocol == "ws://" or brokerprotocol == "wss://")
	var isssl = (brokerprotocol == "ssl://" or brokerprotocol == "wss://")
	var brokerport = ((DEFAULTBROKERPORT_WSS if isssl else DEFAULTBROKERPORT_WS) if iswebsocket else (DEFAULTBROKERPORT_SSL if isssl else DEFAULTBROKERPORT_TCP))
	if brokercomponents[3]:
		brokerport = int(brokercomponents[3].substr(1))
	var brokerpath = brokercomponents[4] if brokercomponents[4] else ""

	common_name = brokerserver

	if iswebsocket:
		websocket = WebSocketPeer.new()
		websocket.supported_protocols = PackedStringArray(["mqttv3.1"])
		var websocketurl = ("wss://" if isssl else "ws://") + brokerserver + ":" + str(brokerport) + brokerpath
		if verbose_level >= 1:
			print("Connecting to websocketurl: %s" % websocketurl)
		var E = websocket.connect_to_url(websocketurl)
		if E != OK:
			if verbose_level >= 1:
				print("ERROR: websocketclient.connect_to_url failed, E=%d" % E)
			return cleanupsockets(false)
		if verbose_level >= 1:
			print("Websocket get_requested_url: %s" % websocket.get_requested_url())
		brokerconnectmode = BCM_WAITING_WEBSOCKET_CONNECTION
	else:
		socket = StreamPeerTCP.new()
		if verbose_level >= 1:
			print("Connecting to %s:%d" % [brokerserver, brokerport])
		var E = socket.connect_to_host(brokerserver, brokerport)
		if E != OK:
			if verbose_level >= 1:
				print("ERROR: socketclient.connect_to_host failed, E=%d" % E)
			return cleanupsockets(false)
		if isssl:
			brokerconnectmode = BCM_WAITING_SSL_SOCKET_CONNECTION
		else:
			brokerconnectmode = BCM_WAITING_SOCKET_CONNECTION
	return true

func disconnect_from_server():
	if brokerconnectmode == BCM_CONNECTED:
		senddata(PackedByteArray([0xE0, 0x00]))
		emit_signal("broker_disconnected")
	cleanupsockets()

func publish(stopic, smsg, retain=false, qos=0):
	var msg = smsg if binarymessages else smsg.to_utf8_buffer()
	var topic = stopic.to_utf8_buffer()

	var pkt = PackedByteArray([CP_PUBLISH | (2 if qos else 0) | (1 if retain else 0), 0x00])
	var sz = 2 + len(topic) + len(msg) + (2 if qos > 0 else 0)
	encoderemaininglength(pkt, sz)
	var remstartpos = len(pkt)
	encodevarstr(pkt, topic)
	if qos > 0:
		pid += 1
		encodeshortint(pkt, pid)
	pkt.append_array(msg)
	assert(len(pkt) - remstartpos == sz)
	senddata(pkt)
	if verbose_level >= 2:
		print("CP_PUBLISH%s%s topic=%s msg=%s" % ["[%d]" % pid if qos else "", " <retain>" if retain else "", stopic, smsg])
	return pid

func subscribe(stopic, qos=0):
	pid += 1
	var topic = stopic.to_utf8_buffer()
	var sz = 2 + 2 + len(topic) + 1
	var pkt = PackedByteArray([CP_SUBSCRIBE, 0x00])
	encoderemaininglength(pkt, sz)
	var remstartpos = len(pkt)
	encodeshortint(pkt, pid)
	encodevarstr(pkt, topic)
	pkt.append(qos)
	assert(len(pkt) - remstartpos == sz)
	if verbose_level >= 1:
		print("SUBSCRIBE[%d] topic=%s" % [pid, stopic])
	senddata(pkt)

func pingreq():
	if verbose_level >= 2:
		print("PINGREQ")
	senddata(PackedByteArray([CP_PINGREQ, 0x00]))

func unsubscribe(stopic):
	pid += 1
	var topic = stopic.to_utf8_buffer()
	var sz = 2 + 2 + len(topic)
	var pkt = PackedByteArray([CP_UNSUBSCRIBE, 0x00])
	encoderemaininglength(pkt, sz)
	var remstartpos = len(pkt)
	encodeshortint(pkt, pid)
	encodevarstr(pkt, topic)
	if verbose_level >= 1:
		print("UNSUBSCRIBE[%d] topic=%s" % [pid, stopic])
	assert(len(pkt) - remstartpos == sz)
	senddata(pkt)

func wait_msg():
	var n = receivedbuffer.size()
	if n < 2:
		return false
	
	# === 최종 디버깅 로그 추가 ===
	if verbose_level >= 2:
		print("[RAW_BUFFER_DEBUG] Buffer size: %d, Content: %s" % [n, str(receivedbuffer)])
	
	var op = receivedbuffer[0]
	var i = 1
	var sz = receivedbuffer[i] & 0x7f
	while (receivedbuffer[i] & 0x80):
		i += 1
		if i == n:
			return false
		sz += (receivedbuffer[i] & 0x7f) << ((i-1)*7)
	i += 1
	
	if verbose_level >= 2:
		print("[PARSING_DEBUG] Opcode: 0x%x, Remaining Length: %d, Header size: %d" % [op, sz, i])
	
	if n < i + sz:
		if verbose_level >= 2:
			print("[PARSING_DEBUG] Incomplete packet. Buffer size %d < Required size %d. Waiting for more data." % [n, i + sz])
		return false

	if op == CP_PINGRESP:
		assert(sz == 0)
		if verbose_level >= 2:
			print("PINGRESP")

	elif op & 0xf0 == 0x30:
		var topic_len = (receivedbuffer[i]<<8) + receivedbuffer[i+1]
		var im = i + 2
		var topic = receivedbuffer.slice(im, im + topic_len).get_string_from_utf8()
		im += topic_len
		var pid1 = 0
		if op & 6:
			pid1 = (receivedbuffer[im]<<8) + receivedbuffer[im+1]
			im += 2
		var data = receivedbuffer.slice(im, i + sz)
		var msg = data if binarymessages else data.get_string_from_utf8()

		if verbose_level >= 2:
			print("received topic=%s msg=%s" % [topic, msg])
		emit_signal("received_message", topic, data if binarymessages else msg)

		if op & 6 == 2:
			senddata(PackedByteArray([0x40, 0x02, (pid1 >> 8), (pid1 & 0xFF)]))
		elif op & 6 == 4:
			assert(0)

	elif op == CP_CONNACK:
		assert(sz == 2)
		var retcode = receivedbuffer[i+1]
		if verbose_level >= 1:
			print("CONNACK ret=%02x" % retcode)
		if retcode == 0x00:
			brokerconnectmode = BCM_CONNECTED
			emit_signal("broker_connected")
		else:
			if verbose_level >= 1:
				print("Bad connection retcode=%d" % retcode)
			brokerconnectmode = BCM_FAILED_CONNECTION
			emit_signal("broker_connection_failed")

	elif op == CP_PUBREC:
		assert(sz == 2)
		var apid = (receivedbuffer[i]<<8) + receivedbuffer[i+1]
		if verbose_level >= 2:
			print("PUBACK[%d]" % apid)
		emit_signal("publish_acknowledge", apid)

	elif op == CP_SUBACK:
		assert(sz == 3)
		var apid = (receivedbuffer[i]<<8) + receivedbuffer[i+1]
		if verbose_level >= 1:
			print("SUBACK[%d] ret=%02x" % [apid, receivedbuffer[i+2]])

	elif op == CP_UNSUBACK:
		assert(sz == 2)
		var apid = (receivedbuffer[i]<<8) + receivedbuffer[i+1]
		if verbose_level >= 1:
			print("UNSUBACK[%d]" % apid)

	else:
		if verbose_level >= 1:
			print("Unknown MQTT opcode op=%x" % op)

	trimreceivedbuffer(i + sz)
	return true

func trimreceivedbuffer(n):
	if n == receivedbuffer.size():
		receivedbuffer = PackedByteArray()
	else:
		assert(n <= receivedbuffer.size())
		receivedbuffer = receivedbuffer.slice(n)
