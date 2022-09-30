package tmpl

import (
	"fmt"
	"strings"
)

const indent = "  "

func ProcessTemplatesGlobal(m map[string]any, parent string, currKey string) string {
	props := GetGlobalProps(m)
	m2 := map[string]any{
		"properties": props,
	}
	out := ProcessTemplates(m2, "lmc.global", "")
	out = strings.ReplaceAll(out, "\n", "\n"+indent)
	out = "%{ if lmc.global != null }\nglobal:" + indent + out + "\n%{ endif }"

	return out
}

func GetGlobalProps(m map[string]any) map[string]any {
	res := make(map[string]any, 0)
	if props, ok := m["properties"]; ok {
		for k, v := range props.(map[string]any) {
			pm := v.(map[string]any)
			if k == "global" {

				if pmv, ok := pm["properties"]; ok {
					for k2, v2 := range pmv.(map[string]any) {
						res[k2] = v2
					}
				}
			} else {
				cm := GetGlobalProps(pm)
				for k, v := range cm {
					res[k] = v
				}
			}
		}
	}
	return res
}
func ProcessTemplates(m map[string]any, parent string, currKey string) string {
	if currKey == "global" {
		return ""
	}
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
			res := ProcessTemplates(v.(map[string]any), pk, k)

			if res != "" {
				outOrig = fmt.Sprintf("%s\n%s", outOrig, res)
			}
		}
	}

	if outOrig != "" {
		out = strings.ReplaceAll(outOrig, "\n", "\n"+indent)
		out = indent + out
	}

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
