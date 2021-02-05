package net.adoptopenjdk.test;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.util.Scanner;
import org.testng.Assert;
import org.testng.annotations.Test;
import org.testng.log4testng.Logger;

/*
 * Tests if the Cuda functionality is enabled in this build.
 * Fit for OpenJ9 builds on Windows, xLinux and pLinux.
 */
@Test(groups={ "level.extended" })
public class CudaEnabledTest {

    private static Logger logger = Logger.getLogger(CudaEnabledTest.class);

    public int getJDKVersion() {
        String javaVersion = System.getProperty("java.version");
        if (javaVersion.startsWith("1.")) {
            javaVersion = javaVersion.substring(2);
        }
        int dotIndex = javaVersion.indexOf('.');
        int dashIndex = javaVersion.indexOf('-');
        try {
            return Integer.parseInt(javaVersion.substring(0, dotIndex > -1 ? dotIndex : dashIndex > -1 ? dashIndex : javaVersion.length()));
        } catch (NumberFormatException e) {
            System.out.println("Cannot determine System.getProperty('java.version')=" + javaVersion + "\n");
            return -1;
        }
    }

    @Test
    public void testIfCudaIsEnabled() {

        logger.info("Starting test to see if CUDA functionality is enabled in this build.");
        
        //Stage 1: Find the location of the j9prt lib file.
        String prtLibDirectory = System.getProperty("java.home");
        String jreSubdir = "";
        if((new File(prtLibDirectory + "/jre")).exists()) {
        	jreSubdir = "/jre";
        }
        if("Linux".contains(System.getProperty("os.name").split(" ")[0])) {
            if(getJDKVersion() == 8) {
                prtLibDirectory += jreSubdir + "/lib/amd64/compressedrefs";
            } else {
                prtLibDirectory += "/lib/compressedrefs";
            }
        }
        //windows
        if("Windows".contains(System.getProperty("os.name").split(" ")[0])) {
            if(getJDKVersion() == 8) {
                //jdk8 32: 
                prtLibDirectory += jreSubdir + "/bin/compressedrefs";
                if(!(new File(prtLibDirectory)).exists()) {
                    //In case of a 32-bit build, or a non-cr build.
                    prtLibDirectory = System.getProperty("java.home") + jreSubdir + "/bin/default";
                }
            } else {
                prtLibDirectory += "/bin/compressedrefs";
            }
        }

        File prtDirObject = new File(prtLibDirectory);
        Assert.assertTrue(prtDirObject.exists(), "Can't find the predicted location of the j9prt lib file. Expected location: " + prtLibDirectory);
        
        String[] prtLibDirectoryFiles = prtDirObject.list();
        String prtFile = null;
        for(int x = 0 ; x < prtLibDirectoryFiles.length ; x++) {
        	if(prtLibDirectoryFiles[x].contains("j9prt")) {
        	    prtFile = prtLibDirectory + "/" + prtLibDirectoryFiles[x];
        	    break;
        	}
        }
        Assert.assertNotNull(prtFile,"Can't find the j9prt lib file in " + prtLibDirectory);
        Assert.assertTrue((new File (prtFile)).exists(), "Found the prt file, but it doesn't exist. Tautology bug.");
        Assert.assertTrue((new File (prtFile)).canRead(), "Found the prt file, but it can't be read. Likely a permissions bug.");
        
        //Stage 2: Iterate through the j9prt lib file to find "cudart".
        //If we find it, then cuda functionality is enabled on this build.
        try {
            BufferedReader prtFileReader = new BufferedReader(new FileReader(prtFile));
            String oneLine = "";
            while ((oneLine = prtFileReader.readLine()) != null) {
                if(oneLine.contains("cudart")) {
                	logger.info("Test completed successfully.");
                    return; //Success!
                }
            }
            prtFileReader.close();
        } catch (FileNotFoundException e) {
            Assert.fail("A file that exists could not be found. This should never happen.");
        } catch (Exception e) {
            throw new Error(e);
        }
        Assert.fail("Cuda should be enabled on this build, but we found no evidence that this was the case.");
    }

}