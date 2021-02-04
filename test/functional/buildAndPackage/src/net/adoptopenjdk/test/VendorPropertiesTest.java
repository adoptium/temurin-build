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

import org.testng.annotations.Test;

import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertNotEquals;
import static org.testng.Assert.assertTrue;

/**
 * Tests whether vendor names and correct URLs appear in all the places they are supposed to.
 */
@Test(groups = {"level.extended"})
public class VendorPropertiesTest {

    private final VmPropertiesChecks vendorChecks;

    public VendorPropertiesTest() {
        Set<VmPropertiesChecks> allPropertiesChecks = new LinkedHashSet<>();
        allPropertiesChecks.add(new AdoptOpenJDKPropertiesChecks());
        allPropertiesChecks.add(new CorrettoPropertiesChecks());

        // TODO: Somehow obtain the vendor name from the outside. Using any JVM properties is not a solution
        // because that's what we want to test here.
        String vendor = "AdoptOpenJDK";
        this.vendorChecks = allPropertiesChecks.stream()
                .filter(checks -> checks.supports(vendor))
                .findFirst()
                .orElseThrow(() -> new AssertionError("No checks found for vendor: " + vendor));
    }

    @Test
    public void javaVersionPrintsVendor() {
        String testJdkHome = System.getenv("TEST_JDK_HOME");
        if (testJdkHome == null) {
            throw new AssertionError("TEST_JDK_HOME is not set");
        }

        List<String> command = new ArrayList<>();
        command.add(String.format("%s/bin/java", testJdkHome));
        command.add("-version");

        try {
            ProcessBuilder processBuilder = new ProcessBuilder(command);
            Process process = processBuilder.start();

            String stderr = StreamUtils.consumeStream(process.getErrorStream());

            if (process.waitFor() != 0) {
                throw new AssertionError("Could not run java -version");
            }

            this.vendorChecks.javaVersion(stderr);
        } catch (InterruptedException | IOException e) {
            throw new RuntimeException("Failed to launch JVM", e);
        }
    }

    @Test
    public void vmPropertiesPointToVendor() {
        this.vendorChecks.javaVendor(System.getProperty("java.vendor"));
        this.vendorChecks.javaVendorUrl(System.getProperty("java.vendor.url"));
        this.vendorChecks.javaVendorUrlBug(System.getProperty("java.vendor.url.bug"));
        this.vendorChecks.javaVendorVersion(System.getProperty("java.vendor.version"));
        this.vendorChecks.javaVmVendor(System.getProperty("java.vm.vendor"));
        this.vendorChecks.javaVmVersion(System.getProperty("java.vm.version"));
    }

    private interface VmPropertiesChecks {
        /**
         * Tests whether the implementation of {@linkplain VmPropertiesChecks} is suitable to verify a JDK.
         *
         * @param vendor Name identifying the vendor.
         */
        boolean supports(String vendor);

        /**
         * Checks whether the output of {@code java -version} is acceptable.
         */
        void javaVersion(String value);

        /**
         * Checks the value of {@code java.vendor}.
         */
        void javaVendor(String value);

        /**
         * Checks the value of {@code java.vendor.url}.
         */
        void javaVendorUrl(String value);

        /**
         * Checks the value of {@code java.vendor.url.bug}.
         */
        void javaVendorUrlBug(String value);

        /**
         * Checks the value of {@code java.vendor.version}.
         */
        void javaVendorVersion(String value);

        /**
         * Checks the value of {@code java.vm.vendor}.
         */
        void javaVmVendor(String value);

        /**
         * Checks the value of {@code java.vm.version}.
         */
        void javaVmVersion(String value);
    }

    private static class AdoptOpenJDKPropertiesChecks implements VmPropertiesChecks {

        @Override
        public boolean supports(String vendor) {
            return vendor.toLowerCase(Locale.US).equals("adoptopenjdk");
        }

        @Override
        public void javaVersion(String value) {
            assertTrue(value.contains("AdoptOpenJDK"));
        }

        @Override
        public void javaVendor(String value) {
            assertEquals(value, "AdoptOpenJDK");
        }

        @Override
        public void javaVendorUrl(String value) {
            assertEquals(value, "https://adoptopenjdk.net/");
        }

        @Override
        public void javaVendorUrlBug(String value) {
            assertEquals(value, "https://github.com/AdoptOpenJDK/openjdk-support/issues");
        }

        @Override
        public void javaVendorVersion(String value) {
            assertNotEquals(value.replaceAll("[^0-9]", "").length(), 0,
                    "java.vendor.version contains no numbers: " + value);
        }

        @Override
        public void javaVmVendor(String value) {
            assertEquals(value, "AdoptOpenJDK");
        }

        @Override
        public void javaVmVersion(String value) {
            assertNotEquals(value.replaceAll("[^0-9]", "").length(), 0,
                    "java.vm.version contains no numbers: " + value);
        }
    }

    private static class CorrettoPropertiesChecks implements VmPropertiesChecks {

        @Override
        public boolean supports(String vendor) {
            return vendor.toLowerCase(Locale.US).startsWith("amazon");
        }

        @Override
        public void javaVersion(String value) {
            assertTrue(value.contains("Corretto"));
        }

        @Override
        public void javaVendor(String value) {
            assertEquals(value, "Amazon.com Inc.");
        }

        @Override
        public void javaVendorUrl(String value) {
            assertEquals(value, "https://aws.amazon.com/corretto/");
        }

        @Override
        public void javaVendorUrlBug(String value) {
            assertTrue(value.startsWith("https://github.com/corretto/corretto"));
        }

        @Override
        public void javaVendorVersion(String value) {
            assertTrue(value.startsWith("Corretto"));
            assertNotEquals(value.replaceAll("[^0-9]", "").length(), 0,
                    "java.vendor.version contains no numbers: " + value);
        }

        @Override
        public void javaVmVendor(String value) {
            assertEquals(value, "Amazon.com Inc.");
        }

        @Override
        public void javaVmVersion(String value) {
            assertNotEquals(value.replaceAll("[^0-9]", "").length(), 0,
                    "java.vm.version contains no numbers: " + value);
        }
    }
}