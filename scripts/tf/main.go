package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"strings"
)

const indent = "  "

func main() {
	m, err := walkSchema("./lm-container")
	if err != nil {
		fmt.Println("chart directory doesn't exist")
	}
	//marshal, err := json.MarshalIndent(m, "", "  ")
	//if err != nil {
	//	return
	//}
	//fmt.Println(string(marshal))
	out := dispPaths(m, "lmc", "")
	fmt.Println(out)
	//marshal, err := json.MarshalIndent(output, "", "  ")
	//if err != nil {
	//	return
	//}
	//fmt.Println(string(marshal))

}

func walkSchema(path string) (map[string]any, error) {
	argusSchemaFile := path + "/values.schema.json"
	bytes, err := ioutil.ReadFile(argusSchemaFile)
	m := map[string]any{}
	if err == nil {
		err = json.Unmarshal(bytes, &m)
		if err != nil {
			return nil, err
		}
	}
	files, err := ioutil.ReadDir(path + "/charts")
	if err != nil {
		return m, nil
	}

	for _, f := range files {
		if f.IsDir() {
			schema, err := walkSchema(path + "/charts/" + f.Name())
			if err != nil {
			}
			mv := m["properties"].(map[string]any)

			mv[f.Name()] = schema
		}
	}

	return m, nil
}
func dispPaths(m map[string]any, parent string, currKey string) string {
	//fmt.Println("traversing:", currKey)
	//fmt.Printf("traversing: %s\n", parent)
	yamlEncode := false
	optional := false
	tfCommentExists := false
	if comment, ok := m["$comment"]; ok {
		val := comment.(string)
		for _, item := range strings.Split(val, " ") {
			if strings.HasPrefix(item, "tf:") && !strings.HasSuffix(item, "-ignore") {
				tfCommentExists = true
				varNm := strings.TrimPrefix(item, "tf:")
				arr := strings.Split(varNm, ",")
				for _, sa := range arr {
					if sa == "yamlencode" {
						yamlEncode = true
					}
					if sa == "optional" {
						optional = true
					}
				}
			}
		}
	}
	out := ""
	outOrig := ""
	if props, ok := m["properties"]; ok {
		propsMap := props.(map[string]any)
		for k, v := range propsMap {
			pk := ""
			if currKey != "" {
				pk = parent + "." + currKey
			} else {
				pk = parent
			}
			res := dispPaths(v.(map[string]any), pk, k)

			if res != "" {
				outOrig = fmt.Sprintf("%s\n%s", outOrig, res)
			}
		}
	}
	//fmt.Println("out:\n", out)
	if outOrig != "" {
		out = strings.ReplaceAll(outOrig, "\n", "\n"+indent)
		out = indent + out
	}
	//fmt.Println("outindent:\n", out)
	res := ""
	absCurrKey := parent + "." + currKey
	if tfCommentExists {
		if optional {
			if out != "" {
				res = fmt.Sprintf("%s{ if %s != null }\n%s:%s\n%s{ endif }", "%", absCurrKey, currKey, out, "%")
				//res = fmt.Sprintf("%s{ if contains(keys(%s), \"%s\" ) && %s != null }\n%s:%s\n%s{ endif }", "%", parent, currKey, absCurrKey, currKey, out, "%")
			} else {
				if yamlEncode {
					res = fmt.Sprintf("%s{ if %s != null }\n%s:\n%s${yamlencode(%s)}\n%s{ endif }", "%", absCurrKey, currKey, indent, absCurrKey, "%")
					//res = fmt.Sprintf("%s{ if contains(keys(%s), \"%s\" ) && %s != null }\n%s:\n%s${yamlencode(%s)}\n%s{ endif }", "%", parent, currKey, absCurrKey, currKey, indent, absCurrKey, "%")
				} else {
					res = fmt.Sprintf("%s{ if %s != null }\n%s: ${%s}\n%s{ endif }", "%", absCurrKey, currKey, absCurrKey, "%")
					//res = fmt.Sprintf("%s{ if contains(keys(%s), \"%s\" ) && %s != null }\n%s: ${%s}\n%s{ endif }", "%", parent, currKey, absCurrKey, currKey, absCurrKey, "%")
				}
			}
		} else {
			if out != "" {
				res = fmt.Sprintf("%s:\n%s%s", currKey, indent, out)
			} else {
				if yamlEncode {
					res = fmt.Sprintf("%s:\n%s${yamlencode(%s)}", currKey, indent, absCurrKey)
				} else {
					res = fmt.Sprintf("%s: %s${%s}", currKey, indent, absCurrKey)
				}
			}
		}
	} else {
		if out != "" {
			if currKey != "" {
				res = fmt.Sprintf("%s:%s", currKey, out)
			} else {
				res = outOrig
			}
		}
	}
	return res
}
