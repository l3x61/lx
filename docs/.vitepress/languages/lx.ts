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
        bind: {
            patterns: [
                {
                    match: "\\b([A-Za-z_][A-Za-z0-9_-]*)\\b([ \\t\\r\\n]*)(=)",
                    captures: {
                        1: { name: "variable.parameter.lx" },
                        3: { name: "keyword.operator.assignment.lx" },
                    },
                },
            ],
        },

        binding: {
            patterns: [
                {
                    name: "meta.binding.lx",
                    begin: "\\blet\\b",
                    beginCaptures: {
                        0: { name: "keyword.declaration.let.lx" },
                    },
                    end: "\\bin\\b",
                    endCaptures: {
                        0: { name: "keyword.declaration.in.lx" },
                    },
                    patterns: [
                        { include: "#bind" },
                        { include: "#literals" },
                        { include: "#operators" },
                        { include: "#keywords" },
                    ],
                },
            ],
        },

        keywords: {
            patterns: [
                { name: "keyword.operator.assignment.lx", match: "λ" },
                { name: "keyword.operator.assignment.lx", match: "\\\\" },
                { name: "keyword.control.conditional.lx", match: "\\bif\\b" },
                { name: "keyword.control.conditional.lx", match: "\\bthen\\b" },
                { name: "keyword.control.conditional.lx", match: "\\belse\\b" },
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
                { name: "keyword.operator.assignment.lx", match: "\\." },
                { name: "keyword.operator.assignment.lx", match: "=" },
                { name: "keyword.operator.arithmetic.lx", match: "\\+" },
                { name: "keyword.operator.arithmetic.lx", match: "-" },
                { name: "keyword.operator.arithmetic.lx", match: "\\*" },
                { name: "keyword.operator.arithmetic.lx", match: "/" },
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
