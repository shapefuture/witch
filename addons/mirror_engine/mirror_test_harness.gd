class_name MirrorTestHarness
extends RefCounted

var passed := 0
var failed := 0
var failures: Array[String] = []

func expect(condition: bool, message: String) -> void:
    if condition:
        passed += 1
    else:
        failed += 1
        failures.append(message)

func expect_eq(actual: Variant, expected: Variant, message: String) -> void:
    expect(actual == expected, "%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func report() -> Dictionary:
    return {"passed": passed, "failed": failed, "total": passed + failed, "failures": failures.duplicate()}
