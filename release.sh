# Automated release script for the Road Generator addon.

echo "Starting release..."

# Affirm on the master branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [ "$BRANCH" != "main" ]; then
    echo -e "Not on master branch, run:"
    echo "git checkout main"
    exit
fi

# TODO: Set up once all gitignores are fully established.
# if [[ `git status --porcelain` ]]; then
#   echo "There are uncommited changes, ending"
#   exit
# fi

git pull main --quiet
echo ""
echo "Current status (should be empty!)"
git status

# TODO(Patrick): Directly run tests here in the future and capture success.
echo "Did you manually run tests?"
read -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1

# Extract the current version number.
VER=$(grep "version=" addons/road-generator/plugin.cfg | awk -F'"' '{print $2}')

echo "Current version detected:"
echo $VER
echo "Is this the correct version to be generating?"
read -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1

echo ""
echo "Creating release with tag: $VER"
gh release create $VER --generate-notes --draft

echo ""
echo "Done, validate release and check download:"
echo "https://github.com/TheDuckCow/godot-road-generator/releases/tag/$VER"
echo "And then close the according milestone, if any"
echo "https://github.com/TheDuckCow/godot-road-generator/milestones"
