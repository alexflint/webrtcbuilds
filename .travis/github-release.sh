#!/bin/bash

set -e

REPO=$1 && shift
RELEASE=$1 && shift
RELEASEFILES=$@
TAG=$RELEASE

if [[ -z "$RELEASEFILES" ]]; then
  echo "Error: No release files provided"
  exit 1
fi

[ -e "$DIR/GITHUBTOKEN" ] && . "$DIR/GITHUBTOKEN"
if [[ -z "$GITHUBTOKEN" ]]; then
  echo "Error: GITHUBTOKEN is not set"
  exit 1
fi

echo -n "Checking release exists for $RELEASE..."

RESULT=`curl -s -w "\n%{http_code}\n"     \
  -H "Authorization: token $GITHUBTOKEN"  \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG"`

RELEASEID=`echo "$RESULT" | jq -s '.[0]? | .id'`

if [[ "`echo "$RESULT" | tail -1`" == "404" || $RELEASEID == 'null' ]]; then
  echo NO
  echo "Creating GitHub release for $RELEASE"

  echo -n "Create release... "
JSON=$(cat <<EOF
{
  "tag_name":         "$TAG",
  "target_commitish": "master",
  "name":             "WebRTC Revision $TAG",
  "draft":            false,
  "prerelease":       false
}
EOF
)
  RESULT=`curl -s -w "\n%{http_code}\n"     \
    -H "Authorization: token $GITHUBTOKEN"  \
    -d "$JSON"                              \
    "https://api.github.com/repos/$REPO/releases"`
  if [ "`echo "$RESULT" | tail -1`" != "201" ]; then
    echo FAILED
    echo "$RESULT"
    exit 1
  fi
  echo DONE
else
  echo YES
fi

RELEASEID=`echo "$RESULT" | jq -s '.[0]? | .id'`
if [[ -z "$RELEASEID" ]]; then
  echo FAILED
  echo "$RESULT"
  exit 1
fi

for FILE in $RELEASEFILES; do
  if [ ! -f $FILE ]; then
    echo "Warning: $FILE not a file"
    continue
  fi
  FILESIZE=`stat -c '%s' "$FILE"`
  FILENAME=`basename $FILE`

  URL=`echo "$RESULT" | jq -r -s ".[0]? | .assets[] | select(.browser_download_url | endswith(\"$FILENAME\")) | .url"`
  if [ ! -z $URL ]; then
    echo -n "Deleting $FILENAME..."
    RESULT=`curl -s -w "%{http_code}\n"                    \
       -H "Authorization: token $GITHUBTOKEN"              \
       -X DELETE $URL`
    if [[ "`echo "$RESULT"`" != "204" ]]; then
      echo FAILED
      echo "$RESULT"
      exit 1
    fi
    echo DONE
  fi

  echo -n "Uploading $FILENAME... "
  RESULT=`curl -s -w "\n%{http_code}\n"                   \
    -H "Authorization: token $GITHUBTOKEN"                \
    -H "Accept: application/vnd.github.manifold-preview"  \
    -H "Content-Type: application/zip"                    \
    --data-binary "@$FILE"                                \
    "https://uploads.github.com/repos/$REPO/releases/$RELEASEID/assets?name=$FILENAME&size=$FILESIZE"`
  if [ "`echo "$RESULT" | tail -1`" != "201" ]; then
    echo FAILED
    echo "$RESULT"
    exit 1
  fi
  echo DONE
done
