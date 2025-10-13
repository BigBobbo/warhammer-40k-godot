extends ENetMultiplayerPeer
class_name MockNetworkPeer

# Mock network peer for testing multiplayer functionality without actual network connections

var mock_peer_id: int = 1
var mock_connection_status: ConnectionStatus = CONNECTION_DISCONNECTED
var sent_packets: Array = []

func _init(peer_id: int = 1) -> void:
	mock_peer_id = peer_id

func get_connection_status() -> ConnectionStatus:
	return mock_connection_status

func get_unique_id() -> int:
	return mock_peer_id

func set_target_peer(id: int) -> void:
	# Mock implementation
	pass

func get_packet() -> PackedByteArray:
	# Mock implementation - return empty packet
	return PackedByteArray()

func put_packet(packet: PackedByteArray) -> int:
	# Mock implementation - store packet for verification
	sent_packets.append(packet)
	return OK

func get_available_packet_count() -> int:
	# Mock implementation
	return 0

func is_server() -> bool:
	return mock_peer_id == 1

func poll() -> void:
	# Mock implementation
	pass

func close() -> void:
	mock_connection_status = CONNECTION_DISCONNECTED

func disconnect_peer(peer: int, force: bool = false) -> void:
	# Mock implementation
	pass

func get_peer(peer_id: int) -> PackedByteArray:
	# Mock implementation
	return PackedByteArray()

# Helper methods for testing

func simulate_connection() -> void:
	mock_connection_status = CONNECTION_CONNECTED

func simulate_disconnection() -> void:
	mock_connection_status = CONNECTION_DISCONNECTED

func get_sent_packet_count() -> int:
	return sent_packets.size()

func clear_sent_packets() -> void:
	sent_packets.clear()