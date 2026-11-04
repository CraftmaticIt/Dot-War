class_name HttpTransport
extends Transport
## Real transport on HTTPRequest nodes attached to `host` (usually the SceneTree root).

const TIMEOUT_S := 10.0

var _host: Node

func _init(host: Node) -> void:
	_host = host

func request(method: String, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	_host.add_child(http)
	var m := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	if http.request(url, headers, m, body) != OK:
		http.queue_free()
		return {"status": 0, "body": ""}
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "body": ""}
	return {"status": int(res[1]), "body": (res[3] as PackedByteArray).get_string_from_utf8()}
