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
// clang-format off
/* jscpd:ignore-start */

#include <stdio.h>
#include <windows.h>
#include <assert.h>
#include <string.h>

/**
 * WindowsUpdateVsVersionInfo
 *
 * Native C app to modify the Windows RC VS_VERSION_INFO of an EXE/DLL
 * Params:
 *   WindowsUpdateVsVersionInfo <file.exe/dll> <key>=<value>
 *     file.exe/dll : Program to be updated
 *     key          : VS_VERSION_INFO String key to be updated
 *     value        : New key value
 *
 * Notes: VStudio API needs to be used so that EXE/DLL object sections get
 * updated correctly resulting in identical length and padding, when necessary.
 *
 * Compile using:
 *   cl WindowsUpdateVsVersionInfo.c version.lib
 */

// Structures for saving existing VS_VERSION_INFO
// Assumes:
//   - Up to 32 String key/values
//   - One binary Var language/codepage pair

#define MAX_KEYS 32

typedef struct {
    WORD              type;
    int               numKeys;
    WCHAR            *key[MAX_KEYS];
    WCHAR            *value[MAX_KEYS];
} STRING_TABLE;

typedef struct {
    WORD              type;
    STRING_TABLE      stringTable;
} STRING_FILE_INFO;

typedef struct {
    WCHAR            *varKey;
    DWORD             var;  // Allow for one binary Lang/CodePage pair
} VAR_FILE_INFO;

typedef struct {
    WORD              type;
    VS_FIXEDFILEINFO  vsFileInfo;
    STRING_FILE_INFO  stringFileInfo;
    VAR_FILE_INFO     varFileInfo;
} VERSION_INFO;

// Declarations
int   updateVSVersionInfo(char *file, WCHAR *wKey, WCHAR *wValue);
short readVSVersionInfo(VERSION_INFO *info, unsigned char * vsBuf);
short createVSVersionInfo(VERSION_INFO *info, unsigned char * vsBuf, int bufLen);

// Main
int main(int argc, char** argv) {
    char *file;
    char *key;
    char *value;
    if (argc > 2) {
        file = argv[1];
        key = strtok(argv[2],"=");
        value = strtok(NULL,"=");
    } else {
        printf("Syntax: WindowsUpdateVsVersionInfo <file> <key>=<value>\n");
        return 1;
    }

    WCHAR *wKey = (WCHAR *)malloc((strlen(key)+1)*sizeof(WCHAR));
    WCHAR *wValue = (WCHAR *)malloc((strlen(value)+1)*sizeof(WCHAR));
    size_t cc = 0;
    mbstowcs_s(&cc, wKey, strlen(key)+1, key, _TRUNCATE);
    mbstowcs_s(&cc, wValue, strlen(value)+1, value, _TRUNCATE);

    // Update the VS_VERSION_INFO wKey value with wValue
    int rc = updateVSVersionInfo(file, wKey, wValue);

    return rc;
}

// Update the VS_VERSION_INFO of the input file
// Changing the WCHAR String value of wKey to the new wValue
int updateVSVersionInfo(char *file, WCHAR *wKey, WCHAR *wValue) {

    printf("Replacing %S key value with %S, in file %s\n", wKey, wValue, file);

    DWORD   dwHandle, dwInfoSize;

    // Get the VS_VERSION_INFO size 
    dwInfoSize = GetFileVersionInfoSize(file, &dwHandle);
    if (dwInfoSize > 0)
    {
        // Allocate vsBuf for existing info
        unsigned char* vsBuf = (unsigned char*)malloc(dwInfoSize);
        // Allocate vsBufNew for creation of new info, add extra 256bytes for enough space
	int newBufLen = dwInfoSize + 256;
        unsigned char* vsBufNew = (unsigned char*)malloc(newBufLen);

        // Get existing version info structure 
        GetFileVersionInfo(file, 0, dwInfoSize, vsBuf);

        LPTSTR pValueBuffer;

        HANDLE hResource = BeginUpdateResource(file, FALSE);
        if (NULL != hResource)
        {
            UINT uTemp;
	    struct {
                WORD wLang;
		WORD wCP;
	    } *lpTranslate;

            //  Get language info
	    if (!VerQueryValue(vsBuf, "\\VarFileInfo\\Translation", (LPVOID *)&lpTranslate, &uTemp) != FALSE)
            {
                printf("Error: Unable to query VS_VERSION_INFO language info\n");
                return 1;
            }

            // Existing version info
            VERSION_INFO vs;

	    short oldLen = -1;
	    short newLen = -1;

            // Read VS_VERSION_INFO
            if ((oldLen = readVSVersionInfo(&vs, vsBuf)) < 0) {
                printf("Error: Unable to read VS_VERSION_INFO\n");
                return 1;
	    }

	    // Update wKey value with wValue
	    for(int k=0; k<vs.stringFileInfo.stringTable.numKeys; k++) {
                if (wcscmp(vs.stringFileInfo.stringTable.key[k], wKey) == 0) {
		    vs.stringFileInfo.stringTable.value[k] = wValue;
                }
	    }

	    // Create new structure for updating file with
	    if ((newLen = createVSVersionInfo(&vs, vsBufNew, newBufLen)) < 0) {
                printf("Error: Unable to create new VS_VERSION_INFO");
		return 1;
            }

	    printf("OldLen = %08x\n", oldLen);
	    printf("NewLen = %08x\n", newLen);

            if (UpdateResource(hResource,
                               RT_VERSION,
                               MAKEINTRESOURCE(VS_VERSION_INFO),
                               lpTranslate->wLang,
                               vsBufNew,
                               newLen) != FALSE)
            {
                EndUpdateResource(hResource, FALSE);
            }
        }
        free(vsBuf);
        free(vsBufNew);
    } else {
        printf("Error: No VS_VERSION_INFO found in %s", file);
	return 1;
    }

    return 0;       
}

// Read the VS_VERSION_INFO from vsBuf and save into info structure
short readVSVersionInfo(VERSION_INFO *info, unsigned char *vsBuf) {

    // Analyse VS_VERSION_INFO
    // See https://learn.microsoft.com/en-us/windows/win32/menurc/vs-versioninfo?source=recommendations

    unsigned char *ptr = vsBuf;

    // WORD wLength
    short versionInfoLen = *((short *)ptr);
    unsigned char * pVersionInfoEnd = ptr + versionInfoLen;
    ptr += 2; 

    // WORD wValueLength
    ptr += 2;

    // WORD wType
    info->type = *((WORD *)ptr);
    ptr += 2;

    // WCHAR - L"VS_VERSION_INFO"
    ptr += ((wcslen(L"VS_VERSION_INFO")+1) * 2); // Length of sz in Unicode

    // Padding to DWORD
    int offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
    if (offset < 4) {
	ptr += offset;
    }

    // VS_FIXEDFILEINFO : https://learn.microsoft.com/en-us/windows/win32/api/verrsrc/ns-verrsrc-vs_fixedfileinfo
    VS_FIXEDFILEINFO *pVsFixedFileInfo = (VS_FIXEDFILEINFO *)ptr;
    info->vsFileInfo = *pVsFixedFileInfo;
    ptr += sizeof(VS_FIXEDFILEINFO);

    // Padding to DWORD
    offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
    if (offset < 4) {
	ptr += offset;
    }

    // Children: StringFileInfo + VarFileInfo

    // StringFileInfo : https://learn.microsoft.com/en-us/windows/win32/menurc/stringfileinfo
    unsigned char * pStringFileInfo = ptr;

    // WORD wLength
    ptr += 2;

    // WORD wValueLength
    ptr += 2;

    // WORD wType
    info->stringFileInfo.type = *((WORD *)ptr);
    ptr += 2;

    // WCHAR szKey : L"StringFileInfo"
    ptr += ((wcslen(L"StringFileInfo")+1) * 2); // Length of sz in Unicode

    // Padding to DWORD
    offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
    if (offset < 4) {
	ptr += offset;
    }

    // StringTable : https://learn.microsoft.com/en-us/windows/win32/menurc/stringtable
    unsigned char * pStringTable = ptr;

    // WORD wLength
    short stringTableLen = *((short*)pStringTable);
    unsigned char * pStringTableEnd = (pStringTable + stringTableLen);
    ptr += 2;

    // WORD wValueLength 
    ptr += 2;

    // WORD wType
    info->stringFileInfo.stringTable.type = *((WORD *)ptr);
    ptr += 2;

    // WCHAR Block Header : L"040904b0"
    ptr += ((wcslen(L"040904b0")+1) * 2); // Length of sz in Unicode

    info->stringFileInfo.stringTable.numKeys = 0;

    // Iterate over the String's : https://learn.microsoft.com/en-us/windows/win32/menurc/string-str
    // Until end of StringTable
    while(ptr < pStringTableEnd) {
        assert(info->stringFileInfo.stringTable.numKeys < MAX_KEYS);

	// Padding to DWORD
	offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
	if (offset < 4) {
	   ptr += offset;
	}

	unsigned char * pString = ptr;

	// WORD wLength
	short stringLen = *((short *)pString);
	ptr += 2;

	// WORD wValueLength
	ptr += 2;

	// WORD wType
	ptr += 2;

	// WCHAR szKey
	WCHAR * pKey = (WCHAR *)ptr;
	printf("String: %S = ", pKey);
        info->stringFileInfo.stringTable.key[info->stringFileInfo.stringTable.numKeys] = pKey;
	ptr += ((wcslen(pKey)+1) * 2);

	// Padding to DWORD
	offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
	if (offset < 4) {
	    ptr += offset;
	}

	// WCHAR szValue
	WCHAR * pValue = (WCHAR *)ptr;
        info->stringFileInfo.stringTable.value[info->stringFileInfo.stringTable.numKeys] = pValue;
	printf("%S\n", pValue);

        info->stringFileInfo.stringTable.numKeys++;
       
	// Move to next String
	ptr = pString + stringLen; 
    }

    // Padding to DWORD
    offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
    if (offset < 4) {
	ptr += offset;
    }

    // VarFileInfo : https://learn.microsoft.com/en-us/windows/win32/menurc/varfileinfo
    unsigned char * pVarFileInfo = ptr;

    // WORD wLength
    short varFileInfoLen = *((short*)pVarFileInfo);
    unsigned char * pVarFileInfoEnd = (pVarFileInfo + varFileInfoLen);
    ptr += 2;

    // WORD wValueLength
    ptr += 2;

    // WORD wType
    ptr += 2;

    // WCHAR : L"VarFileInfo"
    ptr += ((wcslen(L"VarFileInfo")+1) * 2); // Length of sz in Unicode

    int numVar = 0;

    // Iterate over the Var's : https://learn.microsoft.com/en-us/windows/win32/menurc/var-str
    // Until end of VarFileInfo
    while(ptr < pVarFileInfoEnd) {
        // We can only have one Var
        assert(numVar < 1);

	// Padding to DWORD
	offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
	if (offset < 4) {
	   ptr += offset;
	}

	unsigned char * pVar = ptr;

	// WORD wLength
	short varLen = *((short *)pVar);
	unsigned char * pVarEnd = pVar + varLen;
	ptr += 2;

	// WORD wValueLength
	ptr += 2;

	// WORD wType
	ptr += 2;

	// WCHAR szKey
	WCHAR *pKey = (WCHAR *)ptr;
	printf("Var: %S = ", pKey);
	info->varFileInfo.varKey = pKey;
	ptr += ((wcslen(pKey)+1) * 2);

	// Padding to DWORD
	offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
	if (offset < 4) {
	    ptr += offset;
	}

	// Iterate DWORD Value list
	DWORD * pValue = (DWORD *)ptr;
        int numDword = 0;
	while((unsigned char *)pValue < pVarEnd) {
            // Only one DWORD expected
            assert(numDword < 1);

            info->varFileInfo.var = *pValue;

	    printf("DWORD: %02x.%02x.%02x.%02x\n",
		      ( (*pValue) >> 24 ) & 0xff,
		      ( (*pValue) >> 16 ) & 0xff,
		      ( (*pValue) >>  8 ) & 0xff,
		      ( (*pValue) >>  0 ) & 0xff
	    );

            numDword++;
	    pValue++;
	}
	printf("\n");
       
	// Move to next Var
	ptr = pVar + varLen; 
    }

    return (short)(ptr - vsBuf);
}

// Create a new VS_VERSION_INFO in vsBuf from info
short createVSVersionInfo(VERSION_INFO *info, unsigned char * vsBuf, int bufLen) {

    // Analyse VS_VERSION_INFO
    // See https://learn.microsoft.com/en-us/windows/win32/menurc/vs-versioninfo?source=recommendations

    // Clear vsBuf to start with
    memset(vsBuf, 0, bufLen);

    unsigned char *ptr = vsBuf;

    // WORD wLength
    short *versionInfoLen = (short *)ptr;
    ptr += 2;

    // WORD wValueLength : Length of VS_FIXEDFILEINFO
    short *vsInfoValueLen = (short *)ptr;
    *vsInfoValueLen = (short)sizeof(VS_FIXEDFILEINFO);
    ptr += 2;

    // WORD wType
    *((WORD *)ptr) = info->type;
    ptr += 2;

    // WCHAR - L"VS_VERSION_INFO"
    wcscpy((WCHAR *)ptr, L"VS_VERSION_INFO");
    ptr += ((wcslen(L"VS_VERSION_INFO")+1) * 2);

    // Padding to DWORD
    int offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
    if (offset < 4) {
	ptr += offset;
    }

    // VS_FIXEDFILEINFO : https://learn.microsoft.com/en-us/windows/win32/api/verrsrc/ns-verrsrc-vs_fixedfileinfo
    *((VS_FIXEDFILEINFO *)ptr) = info->vsFileInfo;
    ptr += sizeof(VS_FIXEDFILEINFO);

    // Padding to DWORD
    offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
    if (offset < 4) {
	ptr += offset;
    }

    // Children: StringFileInfo + VarFileInfo

    // StringFileInfo : https://learn.microsoft.com/en-us/windows/win32/menurc/stringfileinfo
    unsigned char * pStringFileInfo = ptr;

    // WORD wLength
    short *stringFileInfoLen = (short *)ptr;
    ptr += 2;

    // WORD wValueLength : Always 0
    ptr += 2;

    // WORD wType
    *((WORD *)ptr) = info->stringFileInfo.type;
    ptr += 2;

    // WCHAR szKey : L"StringFileInfo"
    wcscpy((WCHAR *)ptr, L"StringFileInfo");
    ptr += ((wcslen(L"StringFileInfo")+1) * 2);

    // Padding to DWORD
    offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
    if (offset < 4) {
	ptr += offset;
    }

    // StringTable : https://learn.microsoft.com/en-us/windows/win32/menurc/stringtable
    unsigned char * pStringTable = ptr;

    // WORD wLength
    short *stringTableLen = (short*)ptr;
    ptr += 2;

    // WORD wValueLength : Always 0
    ptr += 2;

    // WORD wType
    *((WORD *)ptr) = info->stringFileInfo.stringTable.type;
    ptr += 2;

    // WCHAR Block Header : L"040904b0"
    wcscpy((WCHAR *)ptr, L"040904b0");
    ptr += ((wcslen(L"040904b0")+1) * 2);

    // Iterate over the String's : https://learn.microsoft.com/en-us/windows/win32/menurc/string-str
    for(int k = 0; k < info->stringFileInfo.stringTable.numKeys; k++) {
	// Padding to DWORD
	offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
	if (offset < 4) {
	   ptr += offset;
	}

	unsigned char * pString = ptr;

	// WORD wLength
	short *stringLen = (short *)pString;
	ptr += 2;

	// WORD wValueLength
        *((short *)ptr) = (short)wcslen(info->stringFileInfo.stringTable.value[k]) + 1;
	ptr += 2;

	// WORD wType : 1 "Text"
	*((short *)ptr) = (short)1;
	ptr += 2;

	// WCHAR szKey
	WCHAR * pKey = (WCHAR *)ptr;
	wcscpy((WCHAR *)ptr, info->stringFileInfo.stringTable.key[k]);
	ptr += ((wcslen(info->stringFileInfo.stringTable.key[k])+1) * 2);

	// Padding to DWORD
	offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
	if (offset < 4) {
	    ptr += offset;
	}

	// WCHAR szValue
        wcscpy((WCHAR *)ptr, info->stringFileInfo.stringTable.value[k]);
	ptr += ((wcslen(info->stringFileInfo.stringTable.value[k])+1) * 2);

	// Set stringLen
	(*stringLen) = (short)(ptr - pString);
    }

    *stringTableLen = (short)(ptr - pStringTable);
    *stringFileInfoLen = (short)(ptr - pStringFileInfo);

    // Padding to DWORD
    offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
    if (offset < 4) {
	ptr += offset;
    }

    // VarFileInfo : https://learn.microsoft.com/en-us/windows/win32/menurc/varfileinfo
    unsigned char * pVarFileInfo = ptr;

    // WORD wLength
    short *varFileInfoLen = (short *)pVarFileInfo;
    ptr += 2;

    // WORD wValueLength : Always 0
    ptr += 2;

    // WORD wType : 1 "Text"
    *((short *)ptr) = 1;
    ptr += 2;

    // WCHAR : L"VarFileInfo"
    wcscpy((WCHAR *)ptr, L"VarFileInfo");
    ptr += ((wcslen(L"VarFileInfo")+1) * 2);

    // Set the single Var : https://learn.microsoft.com/en-us/windows/win32/menurc/var-str

    // Padding to DWORD
    offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
    if (offset < 4) {
        ptr += offset;
    }

    unsigned char * pVar = ptr;

    // WORD wLength
    short *varLen = (short *)pVar;
    ptr += 2;

    // WORD wValueLength
    short *varValueLen = (short *)ptr;
    ptr += 2;

    // WORD wType : 0 "Binary"
    ptr += 2;

    // WCHAR szKey
    wcscpy((WCHAR *)ptr, info->varFileInfo.varKey);
    ptr += ((wcslen(info->varFileInfo.varKey)+1) * 2);

    // Padding to DWORD
    offset = 4 - ((ptr-((unsigned char *)vsBuf)) % 4);
    if (offset < 4) {
        ptr += offset;
    }

    *((DWORD *)ptr) = info->varFileInfo.var;
    ptr += sizeof(DWORD); 

    // Set lengths 
    *varValueLen = (short)sizeof(DWORD);
    *varLen = (short)(ptr-pVar);
    *varFileInfoLen = (short)(ptr-pVarFileInfo);
    *versionInfoLen = (short)(ptr-vsBuf);

    return *versionInfoLen;
}
/* jscpd:ignore-end */
