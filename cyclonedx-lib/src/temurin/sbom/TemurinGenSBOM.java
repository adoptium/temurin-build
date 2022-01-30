/*# Licensed under the Apache License, Version 2.0 (the "License");
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
################################################################################
*/
package temurin.sbom;

import org.cyclonedx.BomGeneratorFactory;
import org.cyclonedx.CycloneDxSchema.Version;
import org.cyclonedx.model.*;
import org.cyclonedx.parsers.JsonParser;
import org.cyclonedx.parsers.Parser;
import org.cyclonedx.generators.json.BomJsonGenerator;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Command line tool to construct a CycloneDX SBOM.
 */
public final class TemurinGenSBOM {

    static String FILE_NAME = "testJson.json";

	static String name;
	static String version;
	static String value;
	static String url;
	static String hashes;
	public static Bom bom;
    static String cmd;
    public static Metadata meta = new Metadata();
	public static Property prop1 = new Property();
    public static Property prop2 = new Property();
    public static Component comp = new Component();
    static List<Component> comp1 = new ArrayList<>();
    static List<Hash> hash = new ArrayList<>();
	public static List<Property> prop = new ArrayList<>();
    static Hash hash1 = new Hash(Hash.Algorithm.SHA3_256, hashes);
    static  ExternalReference extRef = new ExternalReference();
    private static FileWriter file;

	private TemurinGenSBOM() {
    }

    public static void main(final String[] args) {


        for (int i = 0; i < args.length; i++) {

            if (args[i].equals("--createNewSBOM")) {
                cmd = "--createNewSBOM";
            }
            else if (args[i].equals("--jsonFile")) {
                FILE_NAME = args[++i];
            }
            else if (args[i].equals("--version")) {
                version = args[++i];
            }
            else if (args[i].equals("--name")) {
                name = args[++i];
            }
            else if (args[i].equals("--value")) {
                value = args[++i];
            }
            else if (args[i].equals("--url")) {
                url = args[++i];
            }
            else if (args[i].equals("--hashes")) {
                hashes = args[++i];
            }
            else if (args[i].equals("--addMetadata")) {   //This is Metadata Component. We can set "name" for Metadata->Component.
                cmd = "addMetadata";
            }
            else if (args[i].equals("--addMetadataProp")) {    //This is MetaData Component --> Property -> name-value: os, arch, variant, scmRef, buildRef, full_version_output, makejdk_any_platform_args
                cmd = "addMetadataProperty";
            }
            else if (args[i].equals("--addComponent")) {    // This is Components->Property: will add name-value.
                cmd = "addComponent";
            }
            else if (args[i].equals("--addComponentProp")) {    // This is Components->Property: will add name-value.
                cmd = "addComponentProp";
            }
            else if (args[i].equals("--addExternalRef")) {
                cmd = "addExtRef";
            }
            else if (args[i].equals("--addComExtRef")) {
                cmd = "addComExtRef";
            }
        }
            switch (cmd) {
            case "--createNewSBOM": {                           //Creates JSON file
               // System.out.println("INSIDE CASE");
                Bom bom = createTestBom(name, version);
                String json = generateBomJson(bom);
                createJSONfile(json, FILE_NAME);
                System.out.println("SBOM: " + json);
            } break;

            case "addMetadata": {//This is Metadata Component --> name
                System.out.println("CASE METADATA");
                Bom bom = addMetadata(name);
                String json = generateBomJson(bom);
                createJSONfile(json, FILE_NAME);
                System.out.println("SBOM: " + json);
            } break;

            case "addMetadataProperty": {                           //This is MetaData--> Component --> Property -> name-value:
                Bom bom = addMetadataProperty(name,value);
                String json = generateBomJson(bom);
                createJSONfile(json, FILE_NAME);
                System.out.println("SBOM: " + json);
                } break;

            case "addComponent": {                                     //This is Components adds name-value pairs to List
                Bom bom = addComponent(name);
                String json = generateBomJson(bom);
                createJSONfile(json, FILE_NAME);
                System.out.println("SBOM: " + json);
               // System.out.println("INSIDE CASE");
                } break;

            case "addComponentProp": {                                     //This is Components adds name-value pairs to List
                Bom bom = addComponentProperty(name,value);
                String json = generateBomJson(bom);
                createJSONfile(json, FILE_NAME);
                System.out.println("SBOM: " + json);
                    // System.out.println("INSIDE CASE");
                } break;

            case "addExtRef": {                                    //This adds extRef to main SBOM
                Bom bom = addExternalReference(url,hashes);
                String json = generateBomJson(bom);
                createJSONfile(json, FILE_NAME);
                System.out.println("SBOM: " + json);
                } break;

            case "addComExtRef": {                                 // This adds extRef to Comp --> extRef
                Bom bom = addComExternalReference(url,hashes);
                String json = generateBomJson(bom);
                createJSONfile(json, FILE_NAME);
                System.out.println("SBOM: " + json);
                } break;
        }
    }
    	
    static Bom createTestBom(String name, String version) {        // Create SBOM, test.JSON file
        Bom bom = new Bom();
        System.out.println(bom.getBomFormat());

        comp.setName(name);
        comp.setVersion(version);
        comp.setType(Component.Type.APPLICATION);
        comp.setGroup("Eclipse Temurin");
        comp.setAuthor("Vendor: Adoptium");

        bom.addComponent(comp);
        return bom;
    }
    static Bom addMetadata(String name) {       // Method to store metadata -->  name
        bom = parseJSONfile();

        comp.setName(name);
        comp.setType(Component.Type.APPLICATION);
        OrganizationalEntity org = new OrganizationalEntity();
        org.setName("Eclipse Foundation");
        org.setUrls(Collections.singletonList("https://www.eclipse.org/"));
        meta.setManufacture(org);
        meta.setComponent(comp);

        bom.setMetadata(meta);
        return bom;
    }
    static Bom addMetadataProperty(String name, String value) { // Method to store metadata --> Properties List --> name-values
        bom = parseJSONfile();git

        meta = bom.getMetadata();
        prop1.setName(name);
        prop1.setValue(value);
        meta.addProperty(prop1);

        bom.setMetadata(meta);
        return bom;
    }

    static Bom addComponent (String name) {           //Method to store Component ->name
        bom = parseJSONfile();

        comp.setType(Component.Type.APPLICATION);
        comp.setName(name);

        bom.addComponent(comp);
        return bom;
    }
    static Bom addComponentProperty( String name, String value) {  // Method to store Component->Property->name-value pairs
    	bom = parseJSONfile();

        prop1.setName(name);
        prop1.setValue(value);
        prop.add(prop1);
        comp.setProperties(prop);

        bom.addProperty(prop1);
        return bom;
    }
	 static Bom addExternalReference(String url, String hashes) {  // Method to store externalReferences: dependency_version_alsa
	    bom = parseJSONfile();

	    hash.add(hash1);
	    extRef.setHashes(hash);
	    extRef.addHash(hash1);
	    extRef.setUrl(url);
	    extRef.setComment("dependency_version_alsa");
	    extRef.setType(ExternalReference.Type.BUILD_SYSTEM);

	    bom.addExternalReference(extRef);
	    return bom;
	 }
	 
     static Bom addComExternalReference(String url, String hashes) {  //Method to store externalReferences to store: openjdk_source
    	bom = parseJSONfile();

        hash.add(hash1);
        extRef.setHashes(hash);
        extRef.addHash(hash1);
        extRef.setUrl(url);
        extRef.setComment("openjdk_source");
        extRef.setType(ExternalReference.Type.BUILD_SYSTEM);
        comp.addExternalReference(extRef);

        bom.addComponent(comp);
        return bom;
    }
    
    static String generateBomJson(final Bom bom) {
    	BomJsonGenerator bomGen = BomGeneratorFactory.createJson(Version.VERSION_13, bom);
        String json = bomGen.toJsonString();
        return json;
    }

    static void createJSONfile(String json, String fileName) {          // Creates testJson.json file 
		try {
			file = new FileWriter(fileName);
			file.write(json);
			file.close(); 
		} catch (Exception e) {
			e.printStackTrace();}
	}
    
    static Bom parseJSONfile() { 	                                     // Returns parse bom
    	  try {
            FileReader reader = new FileReader(FILE_NAME);
    	    JsonParser parser = new JsonParser();
    	    bom = parser.parse(reader); 
    	    }
    	  catch (Exception e){
    		  e.printStackTrace();
    	  }
    	  return bom;
    }
}