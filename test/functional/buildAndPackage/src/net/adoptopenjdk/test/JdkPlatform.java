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

import java.util.Collection;
import java.util.Locale;

public class JdkPlatform {

    private final Architecture architecture;

    private final OperatingSystem operatingSystem;

    public JdkPlatform() {
        this.architecture = detectArchitecture();
        this.operatingSystem = detectOperatingSystem();
    }

    public boolean runsOn(Architecture architecture) {
        return architecture == this.architecture;
    }

    public boolean runsOnAnyArchitecture(Collection<Architecture> architectures) {
        return architectures.contains(this.architecture);
    }

    public boolean runsOn(OperatingSystem operatingSystem) {
        return operatingSystem == this.operatingSystem;
    }

    public boolean runsOn(OperatingSystem operatingSystem, Architecture architecture) {
        return this.runsOn(operatingSystem) && this.runsOn(architecture);
    }

    public boolean runsOnAnyOperatingSystem(Collection<OperatingSystem> operatingSystems) {
        return operatingSystems.contains(this.operatingSystem);
    }

    @Override
    public String toString() {
        return this.operatingSystem.name() + "/" + this.architecture.name();
    }

    private static Architecture detectArchitecture() {
        String arch = normalize(System.getProperty("os.arch"));

        if (arch.matches("^(arm|arm32)$")) {
            return Architecture.ARM;
        }
        if (arch.equals("aarch64")) {
            return Architecture.AARCH64;
        }
        if (arch.equals("ppc64le")) {
            return Architecture.PPC64LE;
        }
        if (arch.equals("riscv")) {
            return Architecture.RISCV;
        }
        if (arch.equals("riscv64")) {
            return Architecture.RISCV64;
        }
        if (arch.matches("^(sparc|sparc32)$")) {
            return Architecture.SPARC32;
        }
        if (arch.matches("^(sparcv9|sparc64)$")) {
            return Architecture.SPARC64;
        }
        if (arch.equals("s390x")) {
            return Architecture.S390X;
        }
        if (arch.matches("^(amd64|em64t|x64|x86_64)$")) {
            return Architecture.X64;
        }
        if (arch.matches("^(x86|i[3-6]86|ia32|x32)$")) {
            return Architecture.X86;
        }

        throw new AssertionError("Unrecognized architecture: " + arch);
    }

    private static OperatingSystem detectOperatingSystem() {
        String osName = normalize(System.getProperty("os.name"));

        if (osName.contains("aix")) {
            return OperatingSystem.AIX;
        }
        if (osName.contains("bsd")) {
            return OperatingSystem.BSD;
        }
        if (osName.contains("linux")) {
            return OperatingSystem.LINUX;
        }
        if (osName.contains("mac")) {
            return OperatingSystem.MACOS;
        }
        if (osName.contains("solaris") || osName.contains("sunos")) {
            return OperatingSystem.SOLARIS;
        }
        if (osName.contains("win")) {
            return OperatingSystem.WINDOWS;
        }

        throw new AssertionError("Unrecognized operating system: " + osName);
    }

    private static String normalize(String str) {
        if (str == null) {
            return "";
        }
        return str.trim().toLowerCase(Locale.US);
    }

    enum Architecture {
        ARM, AARCH64, PPC64LE, RISCV, RISCV64, SPARC32, SPARC64, S390X, X64, X86
    }

    enum OperatingSystem {
        AIX, BSD, LINUX, MACOS, SOLARIS, WINDOWS
    }
}