class_name MirrorEvent
extends RefCounted

var event_id: String
var sequence: int
var event_type: String
var actor_id: String
var target_id: String
var context: Dictionary
var payload: Dictionary
var causes: Array[String]
var effects: Dictionary
var prediction_signature: Array[String]
var author_tag: String
var prev_hash: String
var hash: String
var schema_version: int
var transaction_id: String
var evidence_refs: Array[String]
var definition_hash: String
var catalog_fingerprint: String

func _init(p_event_type: String = "", p_actor_id: String = "", p_target_id: String = "", p_payload: Dictionary = {}):
    event_id = ""
    sequence = 0
    event_type = p_event_type
    actor_id = p_actor_id
    target_id = p_target_id
    context = {}
    payload = p_payload.duplicate(true)
    causes = []
    effects = {}
    prediction_signature = []
    author_tag = ""
    prev_hash = ""
    hash = ""
    schema_version = MirrorDomain.SCHEMA_VERSION
    transaction_id = ""
    evidence_refs = []
    definition_hash = ""
    catalog_fingerprint = ""

func body_dict() -> Dictionary:
    var out := {
        "schema_version": schema_version,
        "event_id": event_id,
        "sequence": sequence,
        "event_type": event_type,
        "actor_id": actor_id,
        "target_id": target_id,
        "context": context.duplicate(true),
        "payload": payload.duplicate(true),
        "causes": causes.duplicate(),
        "effects": effects.duplicate(true),
        "prediction_signature": prediction_signature.duplicate(),
        "author_tag": author_tag,
        "prev_hash": prev_hash,
    }
    if schema_version >= 5:
        out["transaction_id"] = transaction_id
        out["evidence_refs"] = evidence_refs.duplicate()
        out["definition_hash"] = definition_hash
        out["catalog_fingerprint"] = catalog_fingerprint
    return out

func finalize() -> void:
    hash = MirrorHash.sha256(body_dict())

func to_dict() -> Dictionary:
    var out := body_dict()
    out["hash"] = hash
    return out

const _STRING_FIELDS := ["event_id", "event_type", "actor_id", "target_id", "author_tag", "prev_hash", "hash", "transaction_id", "definition_hash", "catalog_fingerprint"]
const _DICT_FIELDS := ["context", "payload", "effects"]
const _STRING_ARRAY_FIELDS := ["causes", "prediction_signature", "evidence_refs"]

# Returns "" for a well-formed serialised event, otherwise a short error code.
# from_dict() used to assume well-formed input, so a corrupt save raised several
# engine-level SCRIPT ERROR traces (Array constructor, duplicate() on a String, typed
# argument conversion) before load failed through an accidental null. A save can be
# damaged by truncation or a bad edit, so it has to fail as a clean rejection.
static func validate_dict(data: Variant) -> String:
    if not data is Dictionary:
        return "not_a_dictionary"
    for field in _STRING_FIELDS:
        if data.has(field) and not data[field] is String:
            return "invalid_field:" + field
    for field in _DICT_FIELDS:
        if data.has(field) and not data[field] is Dictionary:
            return "invalid_field:" + field
    for field in _STRING_ARRAY_FIELDS:
        if data.has(field):
            if not data[field] is Array:
                return "invalid_field:" + field
            for item in data[field]:
                if not item is String:
                    return "invalid_field:" + field
    for field in ["sequence", "schema_version"]:
        if data.has(field) and not (data[field] is int or data[field] is float):
            return "invalid_field:" + field
    return ""

static func from_dict(data: Dictionary) -> MirrorEvent:
    if not validate_dict(data).is_empty():
        return null
    var event := MirrorEvent.new(str(data.get("event_type", "")), str(data.get("actor_id", "")), str(data.get("target_id", "")), data.get("payload", {}))
    event.event_id = str(data.get("event_id", ""))
    event.sequence = int(data.get("sequence", 0))
    event.context = data.get("context", {}).duplicate(true)
    event.causes = Array(data.get("causes", []), TYPE_STRING, "", null)
    event.effects = data.get("effects", {}).duplicate(true)
    event.prediction_signature = Array(data.get("prediction_signature", []), TYPE_STRING, "", null)
    event.author_tag = str(data.get("author_tag", ""))
    event.prev_hash = str(data.get("prev_hash", ""))
    event.hash = str(data.get("hash", ""))
    event.schema_version = int(data.get("schema_version", 4))
    event.transaction_id = str(data.get("transaction_id", ""))
    event.evidence_refs = Array(data.get("evidence_refs", []), TYPE_STRING, "", null)
    event.definition_hash = str(data.get("definition_hash", ""))
    event.catalog_fingerprint = str(data.get("catalog_fingerprint", ""))
    return event
