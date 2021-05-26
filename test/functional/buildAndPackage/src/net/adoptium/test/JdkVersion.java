/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package net.adoptium.test;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Objects;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class JdkVersion {

    /**
     * Matches JDK version numbers that were used before JEP 223 came into effect (JDK 8 and earlier).
     */
    private static final Pattern PRE_223_PATTERN = Pattern.compile(
            "^(?<version>1\\.(?<major>[0-8]+)\\.0(_(?<update>[0-9]+)))(-(?<additional>.*)?)?$"
    );

    /**
     * Int representing x.0.0.0 in typical OpenJDK version string.
     */
    private final int feature;

    /**
     * Int representing 0.x.0.0 in typical OpenJDK version string.
     */
    private final int interim;

    /**
     * Int representing 0.0.x.0 in typical OpenJDK version string.
     */
    private final int update;

    /**
     * Int representing 0.0.0.x in typical OpenJDK version string.
     */
    private final int patch;

    /**
     * The Virtual Machine type being used.
     */
    private final VM vm;

    /**
     * Constructor.
     */
    public JdkVersion() {
        this.vm = detectVM();

        String versionString = System.getProperty("java.version");
        if (versionString.isEmpty()) {
            throw new AssertionError("Property java.version is empty");
        }

        Matcher pre223Matcher = PRE_223_PATTERN.matcher(versionString);
        if (pre223Matcher.matches()) {
            // Handle 8 or earlier.
            this.feature = Integer.parseInt(pre223Matcher.group("major"));
            this.interim = 0;
            this.update = Integer.parseInt(pre223Matcher.group("update"));
            this.patch = 0;
            return;
        }

        // Handle 9 or newer.
        Class<Runtime> runtimeClass = Runtime.class;
        try {
            Method versionMethod = runtimeClass.getDeclaredMethod("version", (Class<?>[]) null);
            Object versionObject = versionMethod.invoke(null, (Object[]) null);
            Class<?> versionClass = versionObject.getClass();

            Method featureMethod;
            Method interimMethod;
            Method updateMethod;
            Method patchMethod;
            try {
                // Java 10 or newer (https://openjdk.java.net/jeps/322)
                featureMethod = versionClass.getDeclaredMethod("feature", (Class<?>[]) null);
                interimMethod = versionClass.getDeclaredMethod("interim", (Class<?>[]) null);
                updateMethod = versionClass.getDeclaredMethod("update", (Class<?>[]) null);
                patchMethod = versionClass.getDeclaredMethod("patch", (Class<?>[]) null);
            } catch (NoSuchMethodException e) {
                // Java 9 (https://openjdk.java.net/jeps/223)
                featureMethod = versionClass.getDeclaredMethod("major", (Class<?>[]) null);
                interimMethod = versionClass.getDeclaredMethod("minor", (Class<?>[]) null);
                updateMethod = versionClass.getDeclaredMethod("security", (Class<?>[]) null);
                patchMethod = null;
            }

            feature = (int) featureMethod.invoke(versionObject, (Object[]) null);
            interim = (int) interimMethod.invoke(versionObject, (Object[]) null);
            update = (int) updateMethod.invoke(versionObject, (Object[]) null);
            if (patchMethod != null) {
                patch = (int) patchMethod.invoke(versionObject, (Object[]) null);
            } else {
                patch = 0;
            }
        } catch (NoSuchMethodException | IllegalAccessException | InvocationTargetException e) {
            throw new AssertionError("Cannot determine JDK version", e);
        }
    }

    /**
     * Retrieve x.0.0.0 from typical OpenJDK version string.
     * @return int feature number
     */
    public int getFeature() {
        return feature;
    }

    /**
     * Retrieve 0.x.0.0 from typical OpenJDK version string.
     * @return int interim number
     */
    public int getInterim() {
        return interim;
    }

    /**
     * Retrieve 0.0.x.0 from typical OpenJDK version string.
     * @return int update number
     */
    public int getUpdate() {
        return update;
    }

    /**
     * Retrieve 0.0.0.x from typical OpenJDK version string.
     * @return int patch number
     */
    public int getPatch() {
        return patch;
    }

    /**
     * Are we running on an OpenJDK feature version
     * that is equal to (or greater than) the
     * supplied int?
     * @param  featureParam  supplied int mentioned above
     * @return boolean       result
     */
    public boolean isNewerOrEqual(final int featureParam) {
        return feature >= featureParam;
    }

    /**
     * Are we running on an OpenJDK feature version
     * that is older than the supplied int?
     * @param  featureParam  supplied int mentioned above
     * @return boolean       result
     */
    public boolean isOlderThan(final int featureParam) {
        return feature < featureParam;
    }

    /**
     * Are we running on an OpenJDK feature version
     * that is greater than the supplied feature int.
     * OR
     * Are we running on the same OpenJDK feature
     * with a greater/equal interim or update versions?
     * @param  featureParam as mentioned above
     * @param  interimParam as mentioned above
     * @param  updateParam  as mentioned above
     * @return boolean result
     */
    public boolean isNewerOrEqualSameFeature(final int featureParam, final int interimParam, final int updateParam) {
        if (feature != featureParam) {
            return false;
        }
        if (interim >= interimParam) {
            return true;
        }
        return update >= updateParam;
    }

    /**
     * Returns all of the version ints concatenated.
     * @return String result
     */
    @Override
    public String toString() {
        return feature + "." + interim + "." + update + "." + patch;
    }

    private static VM detectVM() {
        String vmName = Objects.toString(System.getProperty("java.vm.name"), "");
        if (vmName.matches("^Eclipse OpenJ9 VM$")) {
            return VM.OPENJ9;
        }

        String compilerName = Objects.toString(System.getProperty("sun.management.compiler"), "");
        if (compilerName.matches("^Hotspot(.*)?$")) {
            return VM.HOTSPOT;
        }

        return VM.OTHER;
    }

    /**
     * Does the supplied VM match the VM we're running on?
     * @param  vmParam mentioned above
     * @return boolean result
     */
    public boolean usesVM(final VM vmParam) {
        return vm == vmParam;
    }

    /**
     * Enum listing known VM types that we test.
     */
    enum VM {
        /**
         * OpenJ9 VM from the Eclipse community.
         */
        OPENJ9,

        /**
         * Hotspot VM from the OpenJDK community.
         */
        HOTSPOT,

        /**
         * Unrecognised VM.
         */
        OTHER
    }
}
