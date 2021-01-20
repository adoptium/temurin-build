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

package net.adoptopenjdk.test;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class JdkVersion {

    /**
     * Matches JDK version numbers that were used before JEP 223 came into effect (JDK 8 and earlier).
     */
    private static final Pattern PRE_223_PATTERN = Pattern.compile(
            "^(?<version>1\\.(?<major>[0-8]+)\\.0(_(?<update>[0-9]+)))(-(?<additional>.*)?)?$"
    );

    private final int feature;

    private final int interim;

    private final int update;

    private final int patch;

    public JdkVersion() {
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

    public int getFeature() {
        return feature;
    }

    public int getInterim() {
        return interim;
    }

    public int getUpdate() {
        return update;
    }

    public int getPatch() {
        return patch;
    }

    public boolean isNewerOrEqual(int feature) {
        return this.feature >= feature;
    }

    public boolean isNewerOrEqualSameFeature(int feature, int interim, int update) {
        if (this.feature != feature) {
            return false;
        }
        if (this.interim >= interim) {
            return true;
        }
        return this.update >= update;
    }

    @Override
    public String toString() {
        return feature + "." + interim + "." + update + "." + patch;
    }
}