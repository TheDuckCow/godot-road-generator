# Run all tests using GUT.

cd src
GODOT=$(cat godot_versions.txt)

# Execute tests.
"$GODOT" -s addons/gut/gut_cmdln.gd \
	--path $PWD \
	--no-window \
	-d \
	-gconfig=.gut_editor_config.json

echo ""
if [ "$?" != "0" ]; then
	echo "Tests failed $LINENO."
	exit 1
fi
echo "Tests passed"