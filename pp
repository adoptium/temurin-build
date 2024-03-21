diff --git a/configureBuild.sh b/configureBuild.sh
index 745ffd2..088fca4 100755
--- a/configureBuild.sh
+++ b/configureBuild.sh
@@ -106,16 +106,21 @@ setWorkingDirectory() {
 determineBuildProperties() {
   local build_type=
   local default_build_full_name=
-  # From jdk12 there is no build type in the build output directory name
-  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK12_CORE_VERSION}" ] ||
-    [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK13_CORE_VERSION}" ] ||
-    [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK14_CORE_VERSION}" ] ||
-    [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK15_CORE_VERSION}" ] ||
-    [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDKHEAD_CORE_VERSION}" ]; then
-    build_type=normal
-    default_build_full_name=${BUILD_CONFIG[OS_KERNEL_NAME]}-${BUILD_CONFIG[OS_ARCHITECTURE]}-${BUILD_CONFIG[JVM_VARIANT]}-release
+  if [ -z "${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]}" ] ; then
+    # From jdk12 there is no build type in the build output directory name
+    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK12_CORE_VERSION}" ] ||
+      [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK13_CORE_VERSION}" ] ||
+      [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK14_CORE_VERSION}" ] ||
+      [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK15_CORE_VERSION}" ] ||
+      [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDKHEAD_CORE_VERSION}" ]; then
+      build_type=normal
+      default_build_full_name=${BUILD_CONFIG[OS_KERNEL_NAME]}-${BUILD_CONFIG[OS_ARCHITECTURE]}-${BUILD_CONFIG[JVM_VARIANT]}-release
+    else
+      default_build_full_name=${BUILD_CONFIG[OS_KERNEL_NAME]}-${BUILD_CONFIG[OS_ARCHITECTURE]}-${build_type}-${BUILD_CONFIG[JVM_VARIANT]}-release
+    fi
   else
-    default_build_full_name=${BUILD_CONFIG[OS_KERNEL_NAME]}-${BUILD_CONFIG[OS_ARCHITECTURE]}-${build_type}-${BUILD_CONFIG[JVM_VARIANT]}-release
+    # User defined build output directory
+    default_build_full_name="${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]}"
   fi
   BUILD_CONFIG[BUILD_FULL_NAME]=${BUILD_CONFIG[BUILD_FULL_NAME]:-"$default_build_full_name"}
 }
@@ -234,34 +239,45 @@ processArgumentsforSpecificArchitectures() {
       jvm_variant=server
     fi
 
-    if [ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" -ge 12 ]; then
-      build_full_name=linux-s390x-${jvm_variant}-release
+    local make_autoconf_arg
+    if [ -z "${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]}" ] ; then
+      if [ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" -ge 12 ]; then
+        build_full_name=linux-s390x-${jvm_variant}-release
+      else
+        build_full_name=linux-s390x-normal-${jvm_variant}-release
+      fi
+      make_autoconf_arg="CONF=${build_full_name}"
     else
-      build_full_name=linux-s390x-normal-${jvm_variant}-release
+      build_full_name="${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]}"
+      make_autoconf_arg="SPEC=${build_full_name}/spec.gmk"
     fi
 
     # This is to ensure consistency with the defaults defined in setMakeArgs()
     if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then
-      make_args_for_any_platform="CONF=${build_full_name} DEBUG_BINARIES=true images"
+      make_args_for_any_platform="${make_autoconf_arg} DEBUG_BINARIES=true images"
     # Don't produce a JRE
     elif [ "${BUILD_CONFIG[CREATE_JRE_IMAGE]}" == "false" ]; then
-      make_args_for_any_platform="CONF=${build_full_name} DEBUG_BINARIES=true product-images"
+      make_args_for_any_platform="${make_autoconf_arg} DEBUG_BINARIES=true product-images"
     else
-      make_args_for_any_platform="CONF=${build_full_name} DEBUG_BINARIES=true product-images legacy-jre-image"
+      make_args_for_any_platform="${make_autoconf_arg} DEBUG_BINARIES=true product-images legacy-jre-image"
     fi
     ;;
 
   "ppc64le")
     jvm_variant=server
 
-    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK12_CORE_VERSION}" ] ||
-      [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK13_CORE_VERSION}" ] ||
-      [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK14_CORE_VERSION}" ] ||
-      [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK15_CORE_VERSION}" ] ||
-      [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDKHEAD_CORE_VERSION}" ]; then
-      build_full_name=linux-ppc64-${jvm_variant}-release
+    if [ -z "${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]}" ] ; then
+      if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK12_CORE_VERSION}" ] ||
+        [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK13_CORE_VERSION}" ] ||
+        [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK14_CORE_VERSION}" ] ||
+        [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK15_CORE_VERSION}" ] ||
+        [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDKHEAD_CORE_VERSION}" ]; then
+        build_full_name=linux-ppc64-${jvm_variant}-release
+      else
+        build_full_name=linux-ppc64-normal-${jvm_variant}-release
+      fi
     else
-      build_full_name=linux-ppc64-normal-${jvm_variant}-release
+      build_full_name="${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]}"
     fi
 
     if [ "$(command -v rpm)" ]; then
@@ -289,6 +305,7 @@ processArgumentsforSpecificArchitectures() {
 
   esac
 
+echo "MMMM = $make_args_for_any_platform"
   BUILD_CONFIG[JVM_VARIANT]=${BUILD_CONFIG[JVM_VARIANT]:-$jvm_variant}
   BUILD_CONFIG[BUILD_FULL_NAME]=${BUILD_CONFIG[BUILD_FULL_NAME]:-$build_full_name}
   BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]:-$make_args_for_any_platform}
