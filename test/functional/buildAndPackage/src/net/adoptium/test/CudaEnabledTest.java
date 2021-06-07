package net.adoptium.test;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import org.testng.Assert;
import org.testng.annotations.Test;
import org.testng.log4testng.Logger;

import static net.adoptium.test.JdkPlatform.OperatingSystem;
import static net.adoptium.test.JdkPlatform.Architecture;

/*
 * Tests if the CUDA functionality is enabled in this build.
 * Fit for OpenJ9 builds on Windows, xLinux and pLinux.
 */
@Test(groups = { "level.extended" })
public class CudaEnabledTest {
    /**
     * Message logger for test debug output.
     */
    private static Logger logger = Logger.getLogger(CudaEnabledTest.class);

    /**
     * This is used to identify the OS we're running on.
     */
    private final JdkPlatform jdkPlatform = new JdkPlatform();

    /**
     * Main test method.
     */
    @Test
    public void testIfCudaIsEnabled() throws IOException {

        logger.info("Starting test to see if CUDA functionality is enabled in this build.");

        logger.info("Finding a list of all j9prt files in this build.");
        Set<String> j9prtFiles = findAllPrtFiles();

        logger.info("Scanning each j9prt file found to see if it indicates CUDA enablement.");
        int successes = searchPrtFilesForCudart(j9prtFiles);

        logger.info("j9prt file scanning complete. Assessing results.");
        assessPrtFileSearchResults(successes, j9prtFiles);

        logger.info("Test complete.");
    }

    /**
     * Identifies all j9prt files associated with the JDK we're testing.
     * @return Set<String> The number of prt files found.
     */
    private Set<String> findAllPrtFiles() throws IOException {
        //Stage 1: Find the location of any/all j9prt lib files.
        String testJdkHome = System.getenv("TEST_JDK_HOME");
        if (testJdkHome == null) {
            throw new AssertionError("TEST_JDK_HOME is not set");
        }

        Pattern j9prtPattern;
        if (jdkPlatform.runsOn(OperatingSystem.WINDOWS)) {
            j9prtPattern = Pattern.compile("(.*)\\\\j9prt[0-9][0-9]\\.dll$");
        } else if (jdkPlatform.runsOn(OperatingSystem.MACOS)) {
            j9prtPattern = Pattern.compile("(.*)/libj9prt[0-9][0-9]\\.dylib$");
        } else {
            // If not windows or mac, assume linux file formats.
            j9prtPattern = Pattern.compile("(.*)/libj9prt[0-9][0-9]\\.so$");
        }

        Set<String> j9prtFiles = Files.walk(Paths.get(testJdkHome))
                                      .map(Path::toString)
                                      .filter(name -> j9prtPattern.matcher(name).matches())
                                      .collect(Collectors.toSet());

        Assert.assertFalse(j9prtFiles.isEmpty(), "Can't find a j9prt file anywhere in " + testJdkHome);

        for (String prtFile : j9prtFiles) {
            Assert.assertTrue((new File(prtFile)).exists(),
                "Found the prt file, but it doesn't exist. Tautology bug.");
            Assert.assertTrue((new File(prtFile)).canRead(),
                "Found the prt file, but it can't be read. Likely a permissions bug.");
            logger.info("j9prt file identified: " + prtFile);
        }

        return j9prtFiles;
    }

    /**
     * Takes a list of prt files, and returns the number of files that have CUDA enabled.
     * @param  j9prtFiles The full list of j9prt files found.
     * @return int        The number of prt files with CUDA enabled.
     */
    private int searchPrtFilesForCudart(final Set<String> j9prtFiles) {
        //Stage 2: Iterate through the j9prt files to find "cudart".
        //If we find it in every j9prt file, then CUDA functionality is enabled on every j9 vm in this build.
        int successes = 0;
        for (String prtFile : j9prtFiles) {
            try {
                BufferedReader prtFileReader = new BufferedReader(new FileReader(prtFile));
                String oneLine = "";
                boolean foundCudart = false;
                while ((oneLine = prtFileReader.readLine()) != null) {
                    if (oneLine.contains("cudart")) {
                        logger.info("CUDA-enabled indicator string \'cudart\' was found "
                            + "within this j9prt file: " + prtFile);
                        foundCudart = true;
                        break;
                    }
                }
                prtFileReader.close();
                if (foundCudart) {
                    successes++;
                    continue;
                }
            } catch (FileNotFoundException e) {
                Assert.fail("A file that exists could not be found. This should never happen.");
            } catch (Exception e) {
                throw new Error(e);
            }

            logger.info("CUDA-enabled indicator string \'cudart\' was not found within this j9prt file: " + prtFile);
        }

        return successes;
    }

    /**
     * Takes the list of prt files, and the number of these files that contain "cudart",
     * indicating CUDA enablement. We then assess these results for correctness based on platform.
     * @param  successes  The number of j9prt files with CUDA enabled.
     * @param  j9prtFiles The full list of j9prt files found.
     */
    private void assessPrtFileSearchResults(final int successes, final Set<String> j9prtFiles) {
        if (jdkPlatform.runsOn(OperatingSystem.WINDOWS)) {
            if (jdkPlatform.runsOn(Architecture.X64)) {
                Assert.assertEquals(successes, j9prtFiles.size(),
                    "One or more of the j9prt files in this build is not CUDA-enabled.");
            } else {
                Assert.assertEquals(successes, 0,
                    "This build is CUDA-enabled, but non-x64 Windows builds are not expected to be.");
            }
        } else if (jdkPlatform.runsOn(OperatingSystem.LINUX)) {
            if (jdkPlatform.runsOn(Architecture.X64) || jdkPlatform.runsOn(Architecture.PPC64LE)) {
                Assert.assertEquals(successes, j9prtFiles.size(),
                    "One or more of the j9prt files in this build is not CUDA-enabled.");
            } else {
                Assert.assertEquals(successes, 0, "This build is CUDA-enabled, but was not expected to be.");
            }
        } else {
            Assert.assertEquals(successes, 0, "This build is CUDA-enabled, but was not expected to be.");
        }
    }
}
