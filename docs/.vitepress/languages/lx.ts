import type { LanguageRegistration } from "@shikijs/types";

export const lx: LanguageRegistration = {
    name: "lx",
    scopeName: "source.lx",
    patterns: [
        { include: "#binding" },
        { include: "#keywords" },
        { include: "#literals" },
        { include: "#operators" },
        { include: "#comments" },
    ],
    repository: {
        binding: {
            patterns: [
                {
                    name: "meta.binding.lx",
                    begin: "\\blet\\b",
                    beginCaptures: {
                        0: { name: "keyword.declaration.let.lx" },
                    },
                    end: "(?=;|$)",
                    patterns: [
                        {
                            match: "\\b([A-Za-z_][A-Za-z0-9_]*)\\b(?=\\s*=)",
                            name: "variable.other.definition.lx",
                        },
                        { include: "#literals" },
                        { include: "#operators" },
                        { include: "#keywords" },
                        { include: "#comments" },
                    ],
                },
            ],
        },

        keywords: {
            patterns: [
                { name: "keyword.declaration.let.lx", match: "\\blet\\b" },
                { name: "constant.language.boolean.true.lx", match: "\\btrue\\b" },
                { name: "constant.language.boolean.false.lx", match: "\\bfalse\\b" },
                { name: "variable.language.wildcard.lx", match: "\\b_\\b" },
            ],
        },

        literals: {
            patterns: [
                { include: "#booleans" },
                { include: "#numbers" },
                { include: "#strings" },
            ],
        },

        booleans: {
            patterns: [
                {
                    name: "constant.language.boolean.true.lx",
                    match: "\\btrue\\b",
                },
                {
                    name: "constant.language.boolean.false.lx",
                    match: "\\bfalse\\b",
                },
            ],
        },

        numbers: {
            patterns: [
                {
                    name: "constant.numeric.decimal.lx",
                    match: "\\b[0-9]+\\b",
                },
            ],
        },

        strings: {
            patterns: [
                {
                    name: "string.quoted.double.lx",
                    begin: '"',
                    end: '"',
                    patterns: [
                        {
                            name: "constant.character.escape.lx",
                            match: "\\\\.",
                        },
                    ],
                },
            ],
        },

        operators: {
            patterns: [
                { name: "keyword.operator.assignment.lx", match: "=" },
                { name: "keyword.operator.assignment.lx", match: "=>" },
                { name: "keyword.operator.assignment.lx", match: "\\?" },
                { name: "keyword.operator.assignment.lx", match: "\\.\\.\\." },
                { name: "keyword.operator.assignment.lx", match: "\\.\\." },
                { name: "keyword.operator.arithmetic.lx", match: "\\+" },
                { name: "keyword.operator.arithmetic.lx", match: "-" },
                { name: "keyword.operator.arithmetic.lx", match: "\\*" },
                { name: "keyword.operator.arithmetic.lx", match: "/" },
                { name: "keyword.operator.arithmetic.lx", match: "%" },
                { name: "keyword.operator.arithmetic.lx", match: "\\+\\+" },
                { name: "keyword.operator.comparison.lx", match: "==" },
                { name: "keyword.operator.comparison.lx", match: "!=" },
                { name: "keyword.operator.comparison.lx", match: "<=" },
                { name: "keyword.operator.comparison.lx", match: ">=" },
                { name: "keyword.operator.comparison.lx", match: "<" },
                { name: "keyword.operator.comparison.lx", match: ">" },
                { name: "punctuation.separator.sequence.lx", match: ";" },
                { name: "punctuation.separator.arguments.lx", match: "," },
                { name: "punctuation.section.group.begin.lx", match: "[\\[\\(\\{]" },
                { name: "punctuation.section.group.end.lx", match: "[\\]\\)\\}]" },
            ],
        },

        comments: {
            patterns: [
                {
                    name: "comment.line.number-sign.lx",
                    match: "#.*$",
                },
            ],
        },
    },
};
