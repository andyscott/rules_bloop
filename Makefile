test:
	bazel run //:bloop
	bloop run --verbose \
		src_higherkindness_rules_bloop_example_simple_Simple
	bloop run --verbose \
		src_higherkindness_rules_bloop_example_bazelbuild_rules_scala_Simple


