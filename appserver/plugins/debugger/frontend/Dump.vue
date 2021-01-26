<template>
    <div class="dump">
        <h2>{{value.file}}:{{value.line}}::{{value.func}}()</h2>
        <div v-html=value.dump></div>
        <h3 @click="displayArgs" class="arg-switch">args <small>({{this.display.args ? 'hide' : 'show'}})</small></h3>
        <div v-html=value.args v-if=display.args></div>
        <h3 @click="displayStacktrace" class="arg-switch">stacktrace <small>({{this.display.stacktrace ? 'hide' : 'show'}})</small></h3>
        <div v-html=value.stacktrace v-if=display.stacktrace></div>
    </div>
</template>

<script>
export default {
    data() {
        return {
            "display": {
                "args": false,
                "stacktrace": false,
            },
        }
    },
    props: ["value"],
    methods: {
        displayArgs() {
            this.display.args = !this.display.args;
        },
        displayStacktrace() {
            this.display.stacktrace = !this.display.stacktrace;
        }
    }
}
</script>

<style>
.dump {
    background-color: #D6EDFF;
    border-radius: 6px;
    border-color: #8B95C9;
    border-style: solid;
    border-width: 2px;
    padding: 15px;
    margin-bottom: 20px;
}

.arg-switch {
    cursor: pointer;
}

.arg-switch small {
    text-decoration: underline;
}
</style>
