java_library(
	name = "Foo",
	srcs = ["Foo.java"],
	visibility = ["//visibility:public"],
)

java_library(
	name = "Bar",
	srcs = ["Bar.java"],
	visibility = ["//visibility:public"],
)

java_binary(
	name = "Simple",
	srcs = ["Simple.java"],
	deps = [":Foo", ":Bar"],
	visibility = ["//visibility:public"],
)