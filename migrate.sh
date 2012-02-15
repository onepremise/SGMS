#!/bin/bash
#
# Author: Jason Huntley
# Description: SVN to Git Migration for HA
#
#  Change Log
#
#  Date                   Description                 Initials
#-------------------------------------------------------------
#  01-18-12          Initial Codeing                    JAH
#
#=============================================================

#Set to 1 for verbose debugging
GIT_TRACE=0
export GIT_TRACE

# Feel free to hardcode path and repo name
REPOSITORY=`pwd`
REPOSITORY_NAME="repo"

GIT_LOG="$REPOSITORY/"
LOG_NAME="migration.log"

SVN_URL=$1

Validate () {
  if [ -z "$SVN_URL" ]; then
    echo
    echo "Please provide a valid SVN URL!"
    exit 0
  fi
}

Initialize () {
    _project=$1
    
    GIT_LOG=$GIT_LOG$_project-$LOG_NAME
    
    echo
    echo "Initializing repository for $_project"
    echo
    
    cd $REPOSITORY

    if [ ! -e "$REPOSITORY_NAME" ]; then
      mkdir $REPOSITORY_NAME
    fi
    
   
    if [ -z "$_project" ]; then
      echo
      echo "Since you did not provide a project name, I will only be generating a list of committers. Please feel free to adjust user details, add email address, etc..."
      echo
      
      echo
      echo "Generating Commiters List..."
      echo
      
      svn log -q $SVN_URL | awk -F '|' '/^r/ {sub("^ ", "", $2); sub(" $", "", $2); print $2" = "$2" <"$2">"}' | sort -u > committers.txt
      
      echo
      echo "Commit List Complete."
      echo
      
      if [ -z "$2" ]; then
        echo
        exit 0
      fi         
    fi
    
    if [ -e "$REPOSITORY_NAME/$_project" ]; then
      echo "This project has already been cloned. Please backup and remore the old project before proceeding"
      exit 0
    fi

    if [ -e "$REPOSITORY_NAME/$_project-svn" ]; then
      echo "Removing old clone..."
      rm -rf $REPOSITORY_NAME/$_project-svn/.git
    else
      mkdir $REPOSITORY_NAME/$_project-svn
    fi
}

Clone () {
    _project=$1
    
    echo
    echo "Cloning $_project..."
    echo
    
    _lastRev=`svn info $SVN_URL/trunk/$_project|grep -i 'last changed rev'|sed 's/.*: /r/'`
    echo "Transferring all Revisions. Head: $_lastRev."
    
    git svn clone --authors-file=committers.txt --no-metadata $SVN_URL/trunk $REPOSITORY_NAME/$_project-svn -T $_project -b branch &> $GIT_LOG
    
    _test=`grep -i 'Auto packing' $GIT_LOG | wc -l | tr -d ' '`
    
    if [ $_test = "0" ]; then
      echo
      echo "Clone unexpectedly quit! Restarting fetch..."
      echo
      
      Update $_project $_lastRev
    fi
}

Update () {
    _project=$1-svn
    _lastRev=$2
    
    _i=0
    
    echo
    echo "Updating $_project..."
    echo
    
    cd $REPOSITORY
    cd $REPOSITORY_NAME/$_project
    
    #while ! git svn fetch; do echo "git-svn halted. Restarting..."; done
    git svn fetch >> $GIT_LOG 2>&1
    _test=`grep -i "Auto packing" $GIT_LOG | wc -l | tr -d ' '`
    
    if [ $_test = "0" ]; then
      echo "Verifying last revision $_lastRev..."
      _test=`grep "$_lastRev =" $GIT_LOG  | wc -l | tr -d ' '`
    fi
    
    while [ $_test = "0" ]; do
      echo
      echo "git-svn halted. Restarting $_i...";
      echo
      
      git svn fetch >> $GIT_LOG 2>&1
      
      #RES=$?
      #echo "SVNFETCH RESULT: $RES..."
      #if ! [ $RES -eq 0 ]; then
      
      _test=`grep -i "Auto packing" $GIT_LOG | wc -l | tr -d ' '`
      
      if [ $_test = "0" ]; then
        echo "Verifying last revision $_lastRev..."
        _test=`grep "$_lastRev =" $GIT_LOG | wc -l | tr -d ' '`
        echo $_test...
      fi
      
      let _i=_i+1
    done
    
    echo
    echo "Cleanup unnecessary files and optimize the local repository..."
    echo
    
    git gc
    
    cd $REPOSITORY
    
    echo
    echo "Update Complete..."
    echo
}

CreateGitRepo () {
    _project=$1
    
    echo
    echo "Creating bare git repo for $_project..."
    echo
    
    cd $REPOSITORY
    git init --bare $REPOSITORY_NAME/$_project
    cd $REPOSITORY_NAME/$_project
    git symbolic-ref HEAD refs/heads/trunk
    cd $REPOSITORY
}

PushContentsToGit() {
    _project=$1
    
    echo
    echo "Push contents to git repo for $_project..."
    echo
    
    cd $REPOSITORY/$REPOSITORY_NAME/$_project-svn
    git remote add bare ../$_project
    git config remote.bare.push 'refs/remotes/*:refs/heads/*'
    git push bare
    git remote rm bare
    cd $REPOSITORY
}

RenameTrunkToMaster() {
    _project=$1
      
    echo
    echo "Creating master branch for $_project..."
    echo
    
    cd $REPOSITORY/$REPOSITORY_NAME/$_project
    git branch -m trunk master
    cd $REPOSITORY
}

CleanupBranchesTags() {
  _project=$1

  cd $REPOSITORY/$REPOSITORY_NAME/$_project
  
  git for-each-ref --format='%(refname)' refs/heads/tags | cut -d / -f 4 |
  while read ref
  do
    git tag "$ref" "refs/heads/tags/$ref";
    git branch -D "tags/$ref";
  done
}

BackupSvnClone() {
    _TFILE=".$$.bak"
    _project=$1
    
    echo backup/$_project-svn$_TFILE
      
    echo
    echo "Backing up $_project-svn..."
    echo
    
    cd $REPOSITORY
    
    if [ ! -e "backup" ]; then
      mkdir backup
    fi
    
    
    if [ -e "$REPOSITORY_NAME/$_project-svn" ]; then
      echo "Moving to backup directory..."
      mv $REPOSITORY_NAME/$_project-svn backup/$_project-svn$_TFILE
    fi
}
    
echo
echo "Cloning project $2..."
echo

Validate
Initialize $2
Clone $2
CreateGitRepo $2
PushContentsToGit $2
RenameTrunkToMaster $2
CleanupBranchesTags $2
BackupSvnClone $2

echo
echo "Clone Complete."
echo