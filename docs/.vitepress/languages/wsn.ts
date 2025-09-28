import type { LanguageRegistration } from "@shikijs/types";

export const wsn: LanguageRegistration = {
    name: "wsn",
    scopeName: "source.wsn",
    patterns: [{ include: "#rules" }, { include: "#comments" }],
    repository: {
        rules: {
            patterns: [
                {
                    begin: "^\\s*([A-Za-z0-9_-]+)",
                    beginCaptures: {
                        1: { name: "entity.name.function.wsn" },
                    },
                    end: "(\\.)",
                    endCaptures: {
                        1: { name: "keyword.terminator.wsn" },
                    },
                    patterns: [
                        { include: "#operators" },
                        { include: "#identifiers" },
                        { include: "#strings" },
                        { include: "#comments" },
                    ],
                },
            ],
        },
        strings: {
            patterns: [
                {
                    name: "string.quoted.double.wsn",
                    begin: '"',
                    end: '"',
                    patterns: [
                        {
                            name: "constant.character.escape.wsn",
                            match: "\\.",
                        },
                    ],
                },
            ],
        },
        operators: {
            patterns: [
                { name: "keyword.operator.wsn", match: "=" },
                { name: "keyword.control.wsn", match: "\\|" },
                { name: "keyword.control.wsn", match: "\\(" },
                { name: "keyword.control.wsn", match: "\\)" },
                { name: "keyword.control.wsn", match: "\\[" },
                { name: "keyword.control.wsn", match: "\\]" },
                { name: "keyword.control.wsn", match: "\\{" },
                { name: "keyword.control.wsn", match: "\\}" },
            ],
        },
        identifiers: {
            patterns: [
                {
                    name: "constant.name.wsn",
                    match: "\\bEOF\\b",
                },
                {
                    name: "variable.parameter.wsn",
                    match: "\\b[a-zA-Z0-9_-]+\\b",
                },
            ],
        },
        comments: {
            patterns: [
                {
                    name: "comment.line.lx",
                    match: "#.*$",
                },
            ],
        },
    },
};
