# Minimal assertion helpers shared by the shell test files.
TESTS_RUN=0
TESTS_FAILED=0

assert_equals() {
    local description=$1 actual=$2 expected=$3
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ $actual == "$expected" ]]; then
        echo "  ok   $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL $description"
        echo "         expected: $expected"
        echo "         actual:   $actual"
    fi
}

assert_contains() {
    local description=$1 haystack=$2 needle=$3
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ $haystack == *"$needle"* ]]; then
        echo "  ok   $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL $description"
        echo "         expected to contain: $needle"
        echo "         actual:              $haystack"
    fi
}

assert_not_contains() {
    local description=$1 haystack=$2 needle=$3
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ $haystack != *"$needle"* ]]; then
        echo "  ok   $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL $description"
        echo "         expected NOT to contain: $needle"
    fi
}

assert_ordered() {
    local description=$1 haystack=$2 first=$3 second=$4
    TESTS_RUN=$((TESTS_RUN + 1))
    local before=${haystack%%"$second"*}
    if [[ $haystack == *"$first"* && $haystack == *"$second"* && $before == *"$first"* ]]; then
        echo "  ok   $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL $description ('$first' must precede '$second')"
    fi
}

report() {
    echo
    if (( TESTS_FAILED == 0 )); then
        echo "$TESTS_RUN passed"
        return 0
    fi
    echo "$TESTS_FAILED of $TESTS_RUN FAILED"
    return 1
}
