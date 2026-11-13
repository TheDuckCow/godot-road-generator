# Run all tests using GUT.

GODOT=$(cat godot_versions.txt)

# Execute tests.
"$GODOT" -s addons/gut/gut_cmdln.gd \
	--path $PWD \
	--headless \
	-d \
	-gconfig=.gut_editor_config.json \
	2> ./run_tests_errors.log

if [ "$?" != "0" ]; then
	echo "Tests failed."
	exit 1
fi
echo "Tests passed"