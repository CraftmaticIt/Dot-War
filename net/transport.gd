class_name Transport
extends RefCounted
## HTTP abstraction. Returns {status: int, body: String}; status 0 = network failure.
## Subclasses: HttpTransport (real), FakeTransport (tests).

func request(_method: String, _url: String, _headers: PackedStringArray, _body: String) -> Dictionary:
	return {"status": 0, "body": ""}
