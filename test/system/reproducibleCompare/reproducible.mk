##############################################################################
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##############################################################################
TODO: BINARY location!
SBOM_FILE := $(shell ls $(TEST_ROOT)/../jdkbinary/ | grep "sbom" | grep -v "metadata")
SBOM_FILE := $(TEST_ROOT)/../jdkbinary/$(SBOM_FILE)
ifeq (,$(findstring win,$(SPEC)))
	JDK_FILE := $(shell find $(TEST_ROOT)/../jdkbinary/ -type f -name '*-jdk_*.tar.gz')
else
	JDK_FILE := $(shell find $(TEST_ROOT)/../jdkbinary/ -type f -name '*-jdk_*.zip')
endif

ifneq (,$(findstring linux,$(SPEC)))
	SBOM_FILE := $(subst $(TEST_ROOT)/..,/home/jenkins,$(SBOM_FILE))
	JDK_FILE := $(subst $(TEST_ROOT)/..,/home/jenkins,$(JDK_FILE))
endif