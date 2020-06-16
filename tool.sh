#!/bin/bash

# define constants
EnvironmentAll=(test test1)
EnvironmentDev=(test)

### functions #######################################################

# check if var is element of an array
# usage: if [ $(contains "$var" "${arr[@]}") == "y" ]
function contains () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && echo "y" && return 0; done
  echo "n" && return 1
}

# get a value from a properties file
# value=$(getProperty "file" "key")
function getProperty {
   echo `cat $1 | grep -i -w "^\s*$2" | cut -d'=' -f2`
}

function gitCommit {
  cd "$ROOTPATH"
  PWD=$(pwd)
  echo "Git-PWD: $PWD"
  echo "--------------------------------------------------------------------"
  echo
  STATUS=$(git status |grep 'nothing to commit')
  
  if [ "$STATUS" == "" ]
   then
    echo "Update Github Repository"
    ##git add .
    ##git commit -am "update $pipeline_name in Repository"
    ##git push
  else
    echo "$STATUS"
  fi
}

#####################################################################


# parse script arguments
argsError=""
templateFile=""
parameterFile=""
Environment=""
while getopts ":p:t:e:dcou" opt; do
    case $opt in
        p)
            parameterFile=$OPTARG
            [ ! -f $parameterFile ] && argsError+="parameter file ($parameterFile) does not exist\n"
            ;;
        t)
            templateFile=$OPTARG
            [ ! -f $templateFile ] && argsError+="template file ($templateFile) does not exist\n"
            ;;
        e)
            Environment=$OPTARG
            [ ! $(contains "$Environment" "${EnvironmentAll[@]}") == "y" ] && argsError+="environment should be [${EnvironmentAll[@]}]\n"
            ;;
        d)
            ocDelete=TRUE
            ;;
        c)
            ocCreate=TRUE
            ;;
        o)
            outputOnly=TRUE
            ;;
        u)
            ocStayOnProject=TRUE
            ;;
        \?)
            argsError+="Invalid option: -$OPTARG\n" >&2
            ;;
        :)
            argsError+="Option -$OPTARG requires an argument\n" >&2
            ;;
  esac
done

namespcae="$(dirname $parameterFile)/$(getProperty "$parameterFile" "oc_project")"
app_action="$(dirname $parameterFile)/$(getProperty "$parameterFile" "app_action")"
app_name="$(dirname $parameterFile)/$(getProperty "$parameterFile" "app_name")"
app_name="$(echo $app_name |sed 's/.\///g')"
app_action="$(echo $app_action |sed 's/.\///g')"
Environment="$(echo $Environment |sed 's/.\///g')"

if [ -z "$Environment" ]
then
      pipeline_name="$app_name-$app_action.groovy"
else
     pipeline_name="$app_name-$app_action-$Environment.groovy"
fi

case "$namespcae" in
    *dev* ) folder_name=jenkins-dev-test;;
    * ) echo "no namespace defined";;
esac


# try to find a templateFileName in the properties file
if [ ! "$templateFile" ] &&  [ -f "$parameterFile" ]; then
     templateFile="$(dirname $parameterFile)/$(getProperty "$parameterFile" "oc_template")"
     [ ! -f $templateFile ] && argsError+="template file ($templateFile) does not exist\n"
fi

# check madatory arguments
[ ! $templateFile ] && argsError+="the template file cannot be empty\n"
[ ! $parameterFile ] && argsError+="the parameter file cannot be empty\n"

# check for usage of an env placeholder which should by available by -e option
if [ -z "$Environment" ]; then
    if grep -q '${Environment' $parameterFile; then
        echo -e "\nERROR:"
        echo "you need to define an environment [${EnvironmentAll[@]}]"
        echo "use the -e option"
        echo -e "\nnothing was changed in openshift"
        exit 1
    fi
fi


# check if arguments are complete, if not show help and possible args-error
if [ $# -eq 0 ] || [ "$argsError" != "" ]; then
    echo ""
    echo "usage:"
    echo "  $(basename $0) -p [parameter file] -t [template file] -e [environment] -c -d -o"
    echo ""
    echo "options:"
    echo "  -p  the properties file for the template-parameters"
    echo "  -t  the openshift template yaml-file (optional if given by the parameters) "
    echo "  -e  the environment [${EnvironmentAll[@]}] (optional)"
    echo "  -d  'delete' template (optional, default is 'replace')"
    echo "  -c  'create' template (optional, default is 'replace')"
    echo "  -u  leave current project unchanged, so an replace works faster by ignoring oc project change"
    echo "  -o  output only (optional)"
    if [ "$argsError" != "" ]; then
      echo -e "\nERROR:\n$argsError"
    fi
    exit 1;
fi


#back to root folder
PROPERTYPATH="$(pwd)"
SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cd "$SCRIPTPATH"
cd ../../
ROOTPATH="$(pwd -P)"
cd $PROPERTYPATH
jenkinsPipeline="$ROOTPATH/$folder_name"
# prepare temp folder
tmpDir="$SCRIPTPATH/tmp"

##echo "Debug: PROPERTYPATH:$PROPERTYPATH SCRIPTPATH:$SCRIPTPATH ROOTPATH:$ROOTPATH tmpDir:$tmpDir"

if [ ! -e $tmpDir ]; then
   mkdir -p "$tmpDir"
fi

if [ -f "$tmpDir/jenkinsfile-$pipeline_name" ]; then
    rm -f $tmpDir/*-$pipeline_name  # will not work with mixed win,lin slashes in path
fi

# define Stage dependent on Environment
Stage="undef"
[ $(contains "$Environment" "${EnvironmentDev[@]}") == "y" ] && Stage="dev"
[ $(contains "$Environment" "${EnvironmentQa[@]}") == "y" ] && Stage="qa"
[ $(contains "$Environment" "${EnvironmentProd[@]}") == "y" ] && Stage="prod"

# prepare parameters file (fix whitespaces and resolve Environment dependent variables)
echo "prepare parameter-file: $parameterFile $([ $Environment ] && echo "(environment=$Environment, stage=$Stage)")"
cp $parameterFile $tmpDir/parameter.properties-$pipeline_name
parameterFile=$_   # $_ is the last param of the last command, which is the new tmp-name of the param-file
echo "" >> $parameterFile                                                          # avoid problems with missing newline at the file-end
sed -e "s/^\s*//g" -e "s/\s*=\s*/=/" -i $parameterFile                             # remove leading whitespaces and white spaces around the equals sign
sed -e "/^$/d" -e "/^[#;]/d" -i $parameterFile                                     # remove empty lines and comments
[ $Environment ] && sed "s/^$Environment\.//" -i $parameterFile              # rename properties with Environment marker komo.property= to simple property=...
[ $Environment ] && sed -r "s/(^[^=]*)\.$Environment/\1/" -i $parameterFile  # rename properties with Environment marker property.komo= to simple property=...
[ $Environment ] && sed -r "s/(^[^=]*)\.$Stage/\1/" -i $parameterFile        # rename properties with Stage marker property.komo= to simple property=...
sed "/^[^=]*\.[^=]*=.*/d" -i $parameterFile                                        # remove remaining properties that have a dot in the key (they are obsolete now)


# read desired oc project from properties and use it later (before "oc create")
ocProject=$(getProperty "$parameterFile" "oc_project")
sed "/^oc_.*/d" -i $parameterFile  # remove all "oc_*" parameters, which are not used in the template, only used by this oc-tool


# process the template with oc client and write result into tmp folder
##echo "OC PROCESS: $templateFile, $parameterFile"
templateResult=$tmpDir/template.yaml
oc process -f $templateFile --param-file=$parameterFile -o yaml > $templateResult
if [ $? -ne 0 ]; then
    # there was an oc process error, error output was written by "oc process"
    echo -e "\nnothing was changed in openshift"
    exit 1
fi


# resolve Environment variables (-e option) in template-file, parameter-file and project-name (not in jenkinsfile)
if [ $Environment ]; then
  echo "resolve Environment: $Environment"
  sed -e "s/\${Environment}/$Environment/g" \
      -e "s/\${EnvironmentUpper}/${Environment^^}/g" \
      -i $templateResult -i $parameterFile
  ocProject=$(echo $ocProject | sed "s/\${Environment}/$Environment/g")
fi


# inject jenkinsfiles (inline) into an openshift-template (which should contain a jenkinsfilePath-line in yaml)
grep "jenkinsfilePath:" $templateResult | while IFS= read -r line ; do
    # find needed yaml-indent and jenkinsfile-name
    regex='^([[:space:]]*)jenkinsfilePath:[[:space:]]*([[:graph:]]*)'
    [[ $line =~ $regex ]]
    indent=${BASH_REMATCH[1]}
    jenkinsfileName=${BASH_REMATCH[2]}
    echo "inject jenkinsfile: $jenkinsfileName"

    # The jenkinsfile should be addressed relative to the root of the git-repository, because if the file is not
    # injected here (but rather "jenkinsfile as git-reference"), it won't be found by the openshift pipeline build.

    # git might not be installed, so we need to check for that and give an appropriate error message
    which git > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "$jenkinsfileName was not found, so search relative from a possible git repository root"
        echo "error while resolving jenkinsfile path location: \"git\" is not installed (try using git-bash)"
        echo -e "\nnothing was changed in openshift"
        exit 1
    fi

    # search for a possible git-repository root and use it as absolute path for jenkinsfile
    gitRoot=$(git rev-parse --show-toplevel 2> /dev/null)
    if [ $? -eq 0 ]; then
        jenkinsfileNameAbs="$gitRoot/$jenkinsfileName"
        echo "using jenkinsfile relative to git-root ($gitRoot)"
    else
        # if there is no git, try to find the jenkinsfile relative to the yaml.template
        templateFilePath=$(dirname $(realpath -m $templateFile))
        jenkinsfileNameAbs="$templateFilePath/$jenkinsfileName"
        echo "using jenkinsfile relative to templateFile: $jenkinsfileNameAbs"
    fi

    if [ ! -e $jenkinsfileNameAbs ]; then
        echo "ERROR: jenkinsfile not found ($jenkinsfileNameAbs)"
        echo -e "\nnothing was changed in openshift"
        exit 1
    fi

    # replace git-reference of pipelinefilePath with an inline version of the pipeline
    ##echo "jenkinsfile: |-" > $tmpDir/jenkinsfile
    sed "s/^/  /" $jenkinsfileNameAbs >> $tmpDir/jenkinsfile-$pipeline_name
    sed "s/^/$indent/" -i $tmpDir/jenkinsfile-$pipeline_name
    echo "" >> $tmpDir/jenkinsfile-$pipeline_name

    # replace variables from parameter-file to pipeline dsl (format: ${env.PARAM-NAME})
    while IFS='=' read -r k v; do
        k="\\\${env\.$k}"
        v="$(echo "${v}" | sed -e 's|\\|\\\\|g' -e 's|/|\\/|g' -e 's|\&|\\&|g')"
        sed -e "s/${k}/${v}/g" -i $tmpDir/jenkinsfile-$pipeline_name
    done < $parameterFile
    # maybe the subshell from the while-loop has exit 1, so exit here in the parent shell
    [ $? -ne 0 ] && exit 1

    # prepare match pattern to replace $pipeline_name-section in yaml (escape / and . from filename)
    jenkinsfileName="$(echo ${jenkinsfileName} | sed 's|/|\\/|g'| sed 's|\.|\\\.|g')"
    sed -i -e "/jenkinsfilePath:\s*${jenkinsfileName}\b/ {" -e "r $tmpDir/jenkinsfile" -e 'd' -e '}' $templateResult
done
# maybe the subshell from the while-loop has exit 1, so exit here in the parent shell
[ $? -ne 0 ] && exit 1


# check possible problems in template result (e.g. unresolved  environment, missing -e option)
if grep -q '${Environment' $templateResult; then
    echo -e "\nERROR:"
    echo "unresolved \$Environment in template file"
    echo "use the -e option"
    echo -e "\nnothing was changed in openshift"
    exit 1
fi

# empty line
echo

# just output the path of the template with fully resolved parameters
if [ $outputOnly ]; then
    echo "template file was written to: $templateResult"
    exit 0
fi


#  apply template to project in openshift (delete, create or replace)
#if [ $ocProject ] && [ ! "$ocStayOnProject" ]; then
#    oc project $ocProject
#    [ $? -ne 0 ] && exit 1
#fi
if [ $ocDelete ]; then
    echo "DELETE: pipeline $jenkinsPipeline/$pipeline_name"
    rm $jenkinsPipeline/$pipeline_name
    gitCommit
fi
if [ $ocCreate ]; then
    echo "CREATE: pipeline $jenkinsPipeline/$pipeline_name "
    cp $tmpDir/jenkinsfile-$pipeline_name $jenkinsPipeline/$pipeline_name
    gitCommit
fi
if [ ! "$ocDelete" ] && [ ! "$ocCreate" ]; then
    echo "REPLACE: pipeline $jenkinsPipeline/$pipeline_name"
    cp $tmpDir/jenkinsfile-$pipeline_name $jenkinsPipeline/$pipeline_name
    gitCommit
fi
