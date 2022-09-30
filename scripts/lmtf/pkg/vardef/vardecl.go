package vardef

import (
	"fmt"
	"github.com/logicmonitor/helm-charts-qa/scripts/lmtf/pkg/tmpl"
	"strings"
)

type Type uint32

const (
	Unknown Type = iota
	Object
	String
	Boolean
	List
	Number
	Any
)

func ParseType(typ string) Type {
	switch typ {
	case "string":
		return String
	case "object":
		return Object
	case "number", "integer":
		return Number
	case "boolean":
		return Boolean
	case "Array":
		return List
	case "null":
		return Any
	}
	return Unknown
}

type Item struct {
	Key        string
	IsOptional bool
	Type       Type
	Default    any
	Childs     []Item
}

func (i Item) String() string {
	return fmt.Sprintf("{key: %s, optional: %v, typ: %d, default: %v, childs: %s}", i.Key, i.IsOptional, i.Type, i.Default, i.Childs)
}
func ProcessVarDef(m map[string]any, currKey string) []Item {
	ng := ProcessVarDefNonGlobal(m, currKey)
	props := tmpl.GetGlobalProps(m)
	m2 := map[string]any{
		"properties": props,
	}
	g := ProcessVarDefNonGlobal(m2, "")
	ng = append(ng, Item{
		Key:        "global",
		IsOptional: true,
		Type:       Object,
		Default:    nil,
		Childs:     g,
	})
	return ng
}

func ProcessVarDefNonGlobal(m map[string]any, currKey string) []Item {
	if currKey == "global" {
		return nil
	}
	optional := false
	addDefault := false
	tfCommentExists := false
	if comment, ok := m["$comment"]; ok {
		val := comment.(string)
		for _, item := range strings.Split(val, " ") {
			if strings.HasPrefix(item, "tf:") && !strings.HasSuffix(item, "-ignore") {
				tfCommentExists = true
				varNm := strings.TrimPrefix(item, "tf:")
				arr := strings.Split(varNm, ",")
				for _, sa := range arr {
					if sa == "optional" {
						optional = true
					}
					if sa == "default" {
						addDefault = true
					}
				}
			}
		}
	}
	var res []Item
	if props, ok := m["properties"]; ok {
		propsMap := props.(map[string]any)
		for k, v := range propsMap {
			out := ProcessVarDefNonGlobal(v.(map[string]any), k)
			if len(out) > 0 {
				res = append(res, out...)
			}
		}
	}
	var result []Item
	if tfCommentExists {
		if len(res) > 0 {
			if currKey != "" {
				result = append(result, Item{
					Key:        currKey,
					IsOptional: optional,
					Type:       Object,
					Default:    nil,
					Childs:     res,
				})
			}
		} else {
			var typEnum Type
			if typ, ok := m["type"]; ok {
				typEnum = ParseType(typ.(string))
			}
			var defaultVal any
			if def, ok := m["default"]; ok {
				defaultVal = Convert(typEnum, def)
			}
			i := Item{
				Key:        currKey,
				IsOptional: optional,
				Type:       typEnum,
				Childs:     nil,
			}
			if addDefault {
				i.Default = defaultVal
			}
			result = append(result, i)
		}
	} else {
		if len(res) > 0 {
			if currKey != "" {
				result = append(result, Item{
					Key:        currKey,
					IsOptional: optional,
					Type:       Object,
					Childs:     res,
				})
			} else {
				result = res
			}
		}
	}
	return result
}

func Convert(enum Type, def any) any {
	return def
}

func Dump(items []Item) string {
	res := "variable \"lm-container-configuration\" {\n  type = object({"
	res = fmt.Sprintf("%s\n%s", res, DumpNext(items, 4))
	res = fmt.Sprintf("%s\n})\n}", res)
	return res
}
func DumpNext(items []Item, indent int) string {
	indentStr := strings.Repeat(" ", indent)
	res := ""
	for _, item := range items {
		typPrefix, suffix := GetTypePrefix(item)
		if len(item.Childs) > 0 {
			res = fmt.Sprintf("%s\n%s%s = %s\n%s\n%s%s", res, indentStr, item.Key, typPrefix, DumpNext(item.Childs, indent+2), indentStr, suffix)
		} else {
			res = fmt.Sprintf("%s\n%s%s = %s\n%s%s", res, indentStr, item.Key, typPrefix, indentStr, suffix)
		}
	}
	return res
}

func GetTypePrefix(item Item) (string, string) {
	if len(item.Childs) > 0 {
		if item.IsOptional {
			return "optional(object({", "}))"
		} else {
			return "object({", "})"
		}
	}
	typ := "any"
	switch item.Type {
	case Object:
		typ = "any"
	case Boolean:
		typ = "bool"
	case String:
		typ = "string"
	case List:
		typ = "list(any)"
	case Number:
		typ = "number"
	}
	if item.IsOptional {
		return fmt.Sprintf("optional(%s)", typ), ""
	} else {
		return typ, ""
	}
}
