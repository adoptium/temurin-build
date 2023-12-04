/**
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
################################################################################
*/
package temurin.sbom;

import org.cyclonedx.BomGeneratorFactory;
import org.cyclonedx.CycloneDxSchema;
import org.cyclonedx.generators.json.BomJsonGenerator;
import org.cyclonedx.model.Bom;
import org.cyclonedx.model.Component;
import org.cyclonedx.model.ExternalReference;
import org.cyclonedx.model.formulation.Formula;
import org.cyclonedx.model.Hash;
import org.cyclonedx.model.Metadata;
import org.cyclonedx.model.OrganizationalContact;
import org.cyclonedx.model.OrganizationalEntity;
import org.cyclonedx.model.Property;
import org.cyclonedx.model.Tool;
import org.cyclonedx.parsers.JsonParser;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.Collections;
import java.util.List;
import java.util.LinkedList;

/**
 * Command line tool to construct a CycloneDX SBOM.
 */
public final class TemurinGenSBOM {

    private static boolean verbose = false;

    private TemurinGenSBOM() {
    }
    /**
     * Main entry.
     * @param args Arguments for sbom operation.
     */

    public static void main(final String[] args) {
        String cmd = null;
        String comment = null;
        String compName = null;
        String description = null;
        String fileName = null;
        String hashes = null;
        String name = null;
        String tool = null;
        String type = null;
        String url = null;
        String value = null;
        String version = null;
        
        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("--jsonFile")) {
                fileName = args[++i];
            } else if (args[i].equals("--version")) {
                version = args[++i];
            } else if (args[i].equals("--name")) {
                name = args[++i];
            } else if (args[i].equals("--value")) {
                value = args[++i];
            } else if (args[i].equals("--url")) {
                url = args[++i];
            } else if (args[i].equals("--comment")) {
                comment = args[++i];
            } else if (args[i].equals("--hashes")) {
                hashes = args[++i];
            } else if (args[i].equals("--compName")) {
                compName = args[++i];
            } else if (args[i].equals("--description")) {
                description = args[++i];
            } else if (args[i].equals("--type")) {
                type = args[++i];
            } else if (args[i].equals("--tool")) {
                tool =  args[++i];
            } else if (args[i].equals("--createNewSBOM")) {
                cmd = "createNewSBOM";
            } else if (args[i].equals("--addMetadata")) {        // Metadata Component. We can set "name" for Metadata.
                cmd = "addMetadata";
            } else if (args[i].equals("--addMetadataComponent")) {  // Metadata Component. We can set "name" for Metadata->Component.
                cmd = "addMetadataComponent";
            } else if (args[i].equals("--addMetadataProp")) {    // MetaData Component --> Property -> name-value
                cmd = "addMetadataProperty";
            } else if (args[i].equals("--addComponent")) {       // Components->Property: will add name-value.
                cmd = "addComponent";
            } else if (args[i].equals("--addComponentProp")) {  // Components->Property: will add name-value.
                cmd = "addComponentProp";
            } else if (args[i].equals("--addExternalReference")) {
                cmd = "addExternalReference";
            } else if (args[i].equals("--addComponentExtRef")) {
                cmd = "addComponentExternalReference";
            } else if (args[i].equals("--addMetadataTools")) {
                cmd = "addMetadataTools";
            } else if (args[i].equals("--addFormulation")) {        // Formulation Component. We can set "name" for Formulation.
                cmd = "addFormulation";
            } else if (args[i].equals("--addFormulationComp")) {        // Formulation Component. We can set "name" for Formulation.
                cmd = "addFormulationComp";
            } else if (args[i].equals("--addFormulationCompProp")) {    // Formulation --> Component --> Property --> name-value
                cmd = "addFormulationCompProp";
            } else if (args[i].equals("--verbose")) {
                verbose = true;
            }
        }
        switch (cmd) {
            case "createNewSBOM":                            // Creates JSON file
                Bom bom = createBom();
                writeJSONfile(bom, fileName);
                break;

            case "addMetadata":                              // Adds Metadata --> name
                bom = addMetadata(fileName);
                writeJSONfile(bom, fileName);
                break;

            case "addMetadataComponent":                   // Adds Metadata --> Component--> name
                bom = addMetadataComponent(fileName, name, type, version, description);
                writeJSONfile(bom, fileName);
                break;

            case "addMetadataProperty":                     // Adds MetaData--> Property --> name-value:
                bom = addMetadataProperty(fileName, name, value);
                writeJSONfile(bom, fileName);
                break;

            case "addFormulation":                              // Adds Formulation --> name
                bom = addFormula(fileName);
                writeJSONfile(bom, fileName);
                break;

            case "addFormulationComp":                   // Adds Formulation --> Component--> name
                bom = addFormulaComponent(fileName, name, type);
                writeJSONfile(bom, fileName);
                break;
            case "addFormulationCompProp":                     // Adds Formulation--> Property --> name-value:
                bom = addFormulaComponentProperty(fileName, compName, name, value);
                writeJSONfile(bom, fileName);
                break;

            case "addMetadataTools":
                bom = addMetadataTools(fileName, tool, version);
                writeJSONfile(bom, fileName);
                break;

            case "addComponent":                            // Adds Component
                bom = addComponent(fileName, compName, version, description);
                writeJSONfile(bom, fileName);
                break;

            case "addComponentProp":                       // Adds Components --> name-value pairs
                bom = addComponentProperty(fileName, compName, name, value);
                writeJSONfile(bom, fileName);
                break;

            case "addExternalReference":                                     // Adds external Reference
                bom = addExternalReference(fileName, hashes, url, comment);
                writeJSONfile(bom, fileName);
                break;

            case "addComponentExternalReference":                                  // Adds external Reference to component
                bom = addComponentExternalReference(fileName, hashes, url, comment);
                writeJSONfile(bom, fileName);
                break;
            default:
                System.out.println("Please enter a command.");
        }
    }

    /*
     * Create SBOM file in json format with default "bomFormat" "specVersion" and "version"
     * Add default compo
     */
    static Bom createBom() {
        Bom bom = new Bom();
        return bom;
    }
    static Bom addMetadata(final String fileName) {          // Method to store metadata -->  name
        Bom bom = readJSONfile(fileName);
        Metadata meta = new Metadata();
        OrganizationalEntity org = new OrganizationalEntity();
        org.setName("Eclipse Foundation");
        org.setUrls(Collections.singletonList("https://www.eclipse.org/"));
        meta.setManufacture(org);
        OrganizationalContact auth = new OrganizationalContact();
        auth.setName("Adoptium Temurin");
        meta.addAuthor(auth);
        bom.setMetadata(meta);
        return bom;
    }
    static Bom addMetadataComponent(final String fileName, final String name, final String type, final String version, final String description) {
        Bom bom = readJSONfile(fileName);
        Metadata meta = new Metadata();
        Component comp = new Component();
        Component.Type compType = Component.Type.FRAMEWORK;
        switch (type) {
            case "os":
                compType = Component.Type.OPERATING_SYSTEM;
                break;
            default:
                break;
        }
        comp.setType(compType); // required e.g Component.Type.FRAMEWORK
        comp.setName(name); // required
        comp.setVersion(version);
        comp.setDescription(description);
        meta.setComponent(comp);
        bom.setMetadata(meta);
        return bom;
    }
    static Bom addMetadataProperty(final String fileName, final String name, final String value) {     // Method to store metadata --> Properties List --> name-values
        Bom bom = readJSONfile(fileName);
        Metadata meta = new Metadata();
        Property prop1 = new Property();
        meta = bom.getMetadata();
        prop1.setName(name);
        prop1.setValue(value);
        meta.addProperty(prop1);
        bom.setMetadata(meta);
        return bom;
    }
    static Bom addMetadataTools(final String fileName, final String toolName, final String version) {
        Bom bom = readJSONfile(fileName);
        Metadata meta = new Metadata();
        Tool tool = new Tool();
        meta = bom.getMetadata();
        tool.setName(toolName);
        tool.setVersion(version);
        meta.addTool(tool);
        bom.setMetadata(meta);
        return bom;
    }
    static Bom addComponent(final String fileName, final String compName, final String version, final String description) {      // Method to store Component --> name & single name-value pair
        Bom bom = readJSONfile(fileName);
        Component comp = new Component();
        comp.setName(compName);
        comp.setVersion(version);
        comp.setType(Component.Type.FRAMEWORK);
        comp.setDescription(description);
        comp.setGroup("adoptium.net");
        comp.setAuthor("Adoptium Temurin");
        comp.setPublisher("Eclipse Temurin");
        bom.addComponent(comp);
        return bom;
    }
    static Bom addComponentProperty(final String fileName, final String compName, final String name, final String value) {     // Method to add Component --> Property --> name-value pairs
        Bom bom = readJSONfile(fileName);
        List<Component> componentArrayList = bom.getComponents();
        for (Component item : componentArrayList) {
            if (item.getName().equals(compName)) {
                    Property prop1 = new Property();
                    prop1.setName(name);
                    prop1.setValue(value);
                    item.addProperty(prop1);
            }
        }
        return bom;
    }
    static Bom addExternalReference(final String fileName, final String hashes, final String url, final String comment) {   // Method to store externalReferences: dependency_version_alsa
        Bom bom = readJSONfile(fileName);
        ExternalReference extRef = new ExternalReference();
        Hash hash1 = new Hash(Hash.Algorithm.SHA3_256, hashes);
        extRef.setType(ExternalReference.Type.BUILD_SYSTEM); //required
        extRef.setUrl(url); // required must be a valid URL with protocal
        extRef.setComment(comment);
        extRef.addHash(hash1);
        bom.addExternalReference(extRef);
        return bom;
    }
    static Bom addComponentExternalReference(final String fileName, final String hashes, final String url, final String comment) {  // Method to store externalReferences to store: openjdk_source
        Bom bom = readJSONfile(fileName);
        ExternalReference extRef = new ExternalReference();
        Hash hash1 = new Hash(Hash.Algorithm.SHA3_256, hashes);
        Component comp = new Component();
        extRef.addHash(hash1);
        extRef.setUrl(url);
        extRef.setComment(comment); //"openjdk_source"
        extRef.setType(ExternalReference.Type.BUILD_SYSTEM);
        comp.addExternalReference(extRef);
        bom.addComponent(comp);
        return bom;
    }

    static Bom addFormula(final String fileName) {          // Method to store Formulation
        Bom bom = readJSONfile(fileName);
        List<Formula> formulation = bom.getFormulation();
        if ( formulation == null ) {
          System.out.println("formulation in bom is null, creating one");
          formulation = new LinkedList<Formula>();
          Formula formula  = new Formula();
          formulation.add(formula);
          bom.setFormulation(formulation);
          if ( bom.getFormulation() == null ) System.out.println("Formulation is apparently still null :eyeroll:");
        } else {
          System.out.println("addFormula() has done nothing as there is a already a formulation object in the BoM");
        }
        return bom;
    }

   static Bom addFormulaComponent(final String fileName, final String name, final String type/*, final String version, final String description */) {
// START OF SECTION FROM addFormula
        Bom bom = readJSONfile(fileName);
        List<Formula> formulation = bom.getFormulation();
        if ( formulation == null ) {
          formulation = new LinkedList<Formula>();
          Formula formula  = new Formula();
          formulation.add(formula);
          bom.setFormulation(formulation);
        } else {
          System.out.println("addFormula() has done nothing as there is a already a formulation object in the BoM");
        }
// END OF SECTION FROM addFormula
//        Bom bom = readJSONfile(fileName);
//        List<Formula> formulation = bom.getFormulation();
        // SXA TODO: Not ideal to just be pulling the first entry here
        // But the formula is currently unnamed
        Formula formula = formulation.get(0);
        Component comp = new Component();
        Component.Type compType = Component.Type.FRAMEWORK;
        comp.setType(compType);
        comp.setName(name);
        List<Component> components = formula.getComponents();
        if ( components == null ) {
          components = new LinkedList<Component>();
        }
        components.add(comp);
        formula.setComponents(components);
        formulation.set(0,formula);
        bom.setFormulation(formulation);
        return bom;
    }

    static Bom addFormulaComponentProperty(final String fileName, final String componentName, final String name, final String value) {     // Method to store metadata --> Properties List --> name-values
        Bom bom = readJSONfile(fileName);
        List<Formula> formulation = bom.getFormulation();
        Formula formula = formulation.get(0);
        // Similar to the last method this isn't great as we're assuming there's only one
        // But we can't create more, and they're not named ...
        List<Component> components = formulation.get(0).getComponents();
        for (Component item : components) {

// What if the name wasn't found - this won't create a new one
// Should we skip the "already exists" case and just issue an add?
            if (item.getName().equals(componentName)) {
                    Property prop1 = new Property();
                    prop1.setName(name);
                    prop1.setValue(value);
                    item.addProperty(prop1);
            }
        }
        formula.setComponents(components);
        formulation.set(0, formula);
        bom.setFormulation(formulation);
        return bom;
    }
    static String generateBomJson(final Bom bom) {
        // Use schema v15: https://cyclonedx.org/schema/bom-1.5.schema.json
        BomJsonGenerator bomGen = BomGeneratorFactory.createJson(CycloneDxSchema.Version.VERSION_15, bom);
        String json = bomGen.toJsonString();
        return json;
    }

    static void writeJSONfile(final Bom bom, final String fileName) {          // Creates testJson.json file
        FileWriter file;
        String json = generateBomJson(bom);
        try {
            file = new FileWriter(fileName);
            file.write(json);
            file.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    static Bom readJSONfile(final String fileName) { 	                               // Returns parse bom
        Bom bom = null;
        try {
            FileReader reader = new FileReader(fileName);
            JsonParser parser = new JsonParser();
            bom = parser.parse(reader);
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
           return bom;
        }
    }
}
