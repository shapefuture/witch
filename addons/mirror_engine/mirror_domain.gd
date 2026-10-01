class_name MirrorDomain
extends RefCounted

const SCHEMA_VERSION := 5
const ENGINE_VERSION := "1.3.1"
const MAX_MODEL_DEPTH := 3

enum EpistemicStatus { UNKNOWN, POSSIBLE, SUPPORTED, ESTABLISHED, CONTESTED, DISCONFIRMED, CONTEXTUAL, TRANSFERABLE, UNRESOLVED_BY_DESIGN }
enum EvidenceType { DIRECT, INDIRECT, SECOND_HAND, AMBIGUOUS, CONTRADICTORY, SYMBOLIC }
enum ModelStatus { HYPOTHESIS, SUPPORTED, CONTEXTUAL, CONTRADICTED, REVISED, RETIRED }
enum DiscrepancyKind { OUTCOME, MOTIVE, SCOPE, TIMING, ACTOR, RELATIONAL, SEMANTIC, KNOWLEDGE }
enum ActionType { LOOK, ASK, SHOW, WAIT, GO, CAST, CUSTOM }

static func enum_name(value: int, names: Array[String]) -> String:
    if value >= 0 and value < names.size():
        return names[value]
    return "UNKNOWN"

static func clamp_model_depth(depth: int) -> int:
    return clampi(depth, 0, MAX_MODEL_DEPTH)

# Status enums are semantic, not ordinal. Never use raw enum ordering to decide whether
# a belief/model satisfies a minimum because DISCONFIRMED/CONTRADICTED/RETIRED would
# otherwise accidentally satisfy stronger requirements.
static func epistemic_rank(status: int) -> int:
    match status:
        EpistemicStatus.UNKNOWN: return 0
        EpistemicStatus.DISCONFIRMED: return 0
        EpistemicStatus.POSSIBLE: return 1
        EpistemicStatus.CONTESTED: return 1
        EpistemicStatus.UNRESOLVED_BY_DESIGN: return 1
        EpistemicStatus.CONTEXTUAL: return 2
        EpistemicStatus.TRANSFERABLE: return 2
        EpistemicStatus.SUPPORTED: return 3
        EpistemicStatus.ESTABLISHED: return 4
    return 0

static func epistemic_satisfies(actual: int, minimum: int) -> bool:
    if actual == EpistemicStatus.DISCONFIRMED:
        return false
    return epistemic_rank(actual) >= epistemic_rank(minimum)

static func model_rank(status: int) -> int:
    match status:
        ModelStatus.RETIRED: return 0
        ModelStatus.CONTRADICTED: return 0
        ModelStatus.HYPOTHESIS: return 1
        ModelStatus.CONTEXTUAL: return 2
        ModelStatus.SUPPORTED: return 3
        ModelStatus.REVISED: return 3
    return 0

static func model_satisfies(actual: int, minimum: int) -> bool:
    if actual == ModelStatus.CONTRADICTED or actual == ModelStatus.RETIRED:
        return false
    return model_rank(actual) >= model_rank(minimum)
