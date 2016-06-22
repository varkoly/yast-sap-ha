# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2016 SUSE Linux GmbH, Nuernberg, Germany.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact SUSE Linux GmbH.
#
# ------------------------------------------------------------------------------
#
# Summary: SUSE High Availability Setup for SAP Products: Base YaST Wizard page
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
require 'sap_ha/helpers'
require 'sap_ha/exceptions'

Yast.import 'Wizard'

module SapHA
  module Wizard
    # Base Wizard page class
    class BaseWizardPage
      Yast.import 'UI'
      include Yast::Logger
      include Yast::I18n
      include Yast::UIShortcuts
      include SapHA::Exceptions

      attr_accessor :model

      # Initialize the Wizard page
      def initialize(model)
        log.debug "--- called #{self.class}.#{__callee__} ---"
        @model = model
        @my_model = nil
      end

      # Set the Wizard's contents, help and the back/next buttons
      def set_contents
        log.debug "--- called #{self.class}.#{__callee__} ---"
      end

      # Refresh the view, populating the values from the model
      def refresh_view
      end

      # Refresh model, populating the values from the view
      def update_model
      end

      # Return true if the user can proceed to the next screen
      # Use this if additional verification of the data is needed
      def can_go_next
        true
      end

      # Handle custom user input
      # @param input [Symbol]
      def handle_user_input(input, event)
        log.warn "--- #{self.class}.#{__callee__} : Unexpected user "\
        "input=#{input.inspect}, event=#{event.inspect} ---"
      end

      # Set the contents of the Wizard's page and run the event loop
      def run
        log.debug "--- #{self.class}.#{__callee__} ---"
        set_contents
        refresh_view
        main_loop
      end

      protected

      # Run the main input processing loop
      # Ideally, this method should not be redefined (if we lived in a perfect world)
      def main_loop
        log.debug "--- #{self.class}.#{__callee__} ---"
        loop do
          log.debug "--- #{self.class}.#{__callee__} ---"
          event = Yast::Wizard.WaitForEvent()
          log.error "--- #{self.class}.#{__callee__}: event=#{event} ---"
          input = event["ID"]
          case input
          # TODO: return only :abort, :cancel and :back from here. If the page needs anything else,
          # it should redefine the main_loop
          when :abort, :back, :cancel, :join_cluster
            return input
          when :next, :summary
            update_model
            return input if can_go_next
            dialog_cannot_continue
          else
            handle_user_input(input, event)
          end
        end
      end

      private

      # Create a Wizard page with just a RichText widget on it
      # @param title [String]
      # @param contents [Yast::UI::Term]
      # @param help [String]
      # @param allow_back [Boolean]
      # @param allow_next [Boolean]
      def base_rich_text(title, contents, help, allow_back, allow_next)
        Yast::Wizard.SetContents(
          title,
          base_layout(
            RichText(contents)
          ),
          help,
          allow_back,
          allow_next
        )
      end

      # Create a Wizard page with a simple list selection
      # @param title [String]
      # @param message [String]
      # @param list_contents [Array[String]]
      # @param help [String]
      # @param allow_back [Boolean]
      # @param allow_next [Boolean]
      def base_list_selection(title, message, list_contents, help, allow_back, allow_next)
        Yast::Wizard.SetContents(
          title,
          base_layout_with_label(
            message,
            SelectionBox(Id(:selection_box), Opt(:vstretch), '', list_contents)
          ),
          help,
          allow_back,
          allow_next
        )
      end

      # Obtain a property of a widget
      # @param widget_id [Symbol]
      # @param property [Symbol]
      def value(widget_id, property = :Value)
        Yast::UI.QueryWidget(Id(widget_id), property)
      end

      def set_value(widget_id, value, property = :Value)
        Yast::UI.ChangeWidget(Id(widget_id), property, value)
      end

      # Base layout that wraps all the widgets
      def base_layout(contents)
        log.debug "--- #{self.class}.#{__callee__} ---"
        HBox(
          HSpacing(3),
          # HStretch(),
          contents,
          HSpacing(3)
          # HStretch()
        )
      end

      # Base layout that wraps all the widgets
      def base_layout_with_label(label_text, contents)
        log.debug "--- #{self.class}.#{__callee__} ---"
        base_layout(
          VBox(
            HSpacing(80),
            VSpacing(1),
            Left(Label(label_text)),
            VSpacing(1),
            contents,
            VSpacing(Opt(:vstretch))
          )
        )
      end

      # A dynamic popup showing the message and the widgets.
      # Runs the validators method to check user input
      # @param message [String] a message to display
      # @param validators [Lambda] validation routine
      # @param widgets [Array] widgets to show
      def base_popup(message, validators, *widgets)
        log.debug "--- #{self.class}.#{__callee__} ---"
        input_widgets = [:InputField, :TextEntry, :Password,
                         :SelectionBox, :MinWidth, :MinHeight, :MinSize]
        Yast::UI.OpenDialog(
          VBox(
            Label(message),
            *widgets,
            Yast::Wizard.CancelOKButtonBox
          )
        )
        loop do
          ui = Yast::UI.UserInput
          case ui
          when :ok
            parameters = {}
            widgets.select { |w| input_widgets.include? w.value }.each do |w|
              # if the actual widget is wrapped within a size widget
              if w.value == :MinWidth || w.value == :MinHeight
                w = w.params[1]
              elsif w.value == :MinSize
                w = w.params[2]
              end
              # TODO: check once more, just to be sure :)
              # next unless input_widgets.include? w
              id = w.params.find do |parameter|
                parameter.respond_to?(:value) && parameter.value == :id
              end.params[0]
              parameters[id] = Yast::UI.QueryWidget(Id(id), :Value)
            end
            log.debug "--- #{self.class}.#{__callee__} popup parameters: #{parameters} ---"
            if validators && !@model.no_validators
              ret = validators.call(parameters)
              unless ret.empty?
                show_dialog_errors(ret)
                next
              end
            end
            Yast::UI.CloseDialog
            return parameters
          when :cancel
            Yast::UI.CloseDialog
            return nil
          end
        end
      end

      # Create a true/false combo box
      # @param id_ [Symbol] widget's ID
      # @param label [String] combo's label
      # @param true_ [Boolean] 'true' option is selected
      def base_true_false_combo(id_, label = '', true_ = true)
        ComboBox(Id(id_), label,
          [
            Item(Id(:true), 'true', true_),
            Item(Id(:false), 'false', !true_)
          ]
        )
      end

      # Prompt the user for the password
      # Do not use base_popup because it logs the input!
      # @param message [String] additional prompt message
      def password_prompt(message)
        Yast::UI.OpenDialog(
          VBox(
            Label(message),
            Password(Id(:password), 'Password:', ''),
            Yast::Wizard.CancelOKButtonBox
          )
        )
        ui = Yast::UI.UserInput
        case ui
        when :cancel
          Yast::UI.CloseDialog
          return nil
        when :ok
          pass = value(:password)
          Yast::UI.CloseDialog
          return nil if pass.empty?
          pass
        end
      end

      def show_dialog_errors(error_list, title = "Invalid input")
        log.error "--- #{self.class}.#{__callee__}: #{error_list} ---"
        html_str = "<ul>\n"
        html_str << error_list.map { |e| "<li>#{e}</li>" }.join("\n")
        html_str << "</ul>"
        Yast::Popup.LongText(title, RichText(html_str), 60, 17)
      end

      def dialog_cannot_continue(message=nil)
        unless message
          message = "<p>Configuration is invalid or incomplete and the Wizard
          cannot proceed to the next step.</p><p>Please review the settings.</p>"
        end
        Yast::Popup.LongText("Invalid input", RichText(message), 40, 5)
      end
    end
  end
end