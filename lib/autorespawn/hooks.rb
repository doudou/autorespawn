class Autorespawn
    # Override of the global Hooks behaviour w.r.t. blocks. Blocks are evaluated
    # in their definition context in Autorespawn instead of the default evaluation in
    # the context of the receiver
    module Hooks
        include ::Hooks

        def self.included(base)
            base.class_eval do
                extend Uber::InheritableAttr
                extend ClassMethods
                inheritable_attr :_hooks
                self._hooks= HookSet.new
            end
        end

        module ClassMethods
            include ::Hooks::ClassMethods

            def define_hooks(callback, scope: lambda { |c, s| s if !c.proc? })
                super
            end
        end
    end
end

