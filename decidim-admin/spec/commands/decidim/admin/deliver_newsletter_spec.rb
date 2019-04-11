# frozen_string_literal: true

require "spec_helper"

module Decidim::Admin
  describe DeliverNewsletter do
    describe "call" do
      let(:organization) { create(:organization) }
      let(:newsletter) do
        create(:newsletter,
               organization: organization,
               body: Decidim::Faker::Localized.sentence(3))
      end
      let(:current_user) { create :user, :admin, :confirmed, organization: organization }
      let(:scopes) do
        create_list(:scope, 5, organization: organization)
      end

      let(:send_to_all_users) { false }
      let(:send_to_followers) { false }
      let(:send_to_participants) { false }
      let(:participatory_space_types) { [] }
      let(:scope_ids) { [] }

      let(:form_params) do
        {
          send_to_all_users: send_to_all_users,
          send_to_followers: send_to_followers,
          send_to_participants: send_to_participants,
          participatory_space_types: participatory_space_types,
          scope_ids: scope_ids
        }
      end

      let(:form) do
        SelectiveNewsletterForm.from_params(
          form_params
        ).with_context(
          current_organization: organization,
          current_user: current_user
        )
      end

      let(:command) { described_class.new(newsletter, form, current_user) }

      shared_examples_for "selective newsletter" do
        context "when everything is ok" do
          it "updates the counters and delivers to the right users" do
            clear_emails
            expect(emails.length).to eq(0)

            perform_enqueued_jobs { command.call }

            expect(emails.length).to eq(5)

            deliverable_users.each do |user|
              email = emails.find { |e| e.to.include? user.email }
              expect(email_body(email)).to include(newsletter.body[user.locale])
            end

            newsletter.reload
            expect(newsletter.total_deliveries).to eq(5)
            expect(newsletter.total_recipients).to eq(5)
          end

          it "logs the action", versioning: true do
            expect(Decidim.traceability)
              .to receive(:perform_action!)
              .with("deliver", newsletter, current_user)
              .and_call_original

            expect do
              perform_enqueued_jobs { command.call }
            end.to change(Decidim::ActionLog, :count)

            action_log = Decidim::ActionLog.last
            expect(action_log.version).to be_present
            expect(action_log.version.event).to eq "update"
          end
        end
      end

      context "when sending to all users" do
        let(:send_to_all_users) { true }

        context "without scopes segment" do
          let!(:deliverable_users) do
            create_list(:user, 5, :confirmed, organization: organization, newsletter_notifications_at: Time.current)
          end

          let!(:not_deliverable_users) do
            create_list(:user, 3, organization: organization, newsletter_notifications_at: nil)
          end

          let!(:unconfirmed_users) do
            create_list(:user, 3, organization: organization, newsletter_notifications_at: Time.current)
          end

          it_behaves_like "selective newsletter"
        end

        context "with scopes segment" do
          let(:scope_ids) { scopes.pluck(:id) }

          context "when interests match the selected scopes" do
            let!(:deliverable_users) do
              create_list(:user, 5, :confirmed, organization: organization, newsletter_notifications_at: Time.current, extended_data: { "interested_scopes" => scopes.first.id })
            end

            it_behaves_like "selective newsletter"
          end

          context "when interest not match the selected scopes" do
            let(:user_interset) { create(:scope, organization: organization) }
            let!(:deliverable_users) do
              create_list(:user, 5, :confirmed, organization: organization, newsletter_notifications_at: Time.current, extended_data: { "interested_scopes" => user_interset.id })
            end

            it "is not valid" do
              expect { command.call }.to broadcast(:no_recipients)
            end
          end
        end
      end

      context "when sending to followers" do
        let(:send_to_followers) { true }

        context "when no spaces selected " do
          it "is not valid" do
            expect { command.call }.to broadcast(:invalid)
          end
        end

        context "when spaces selected" do
          let(:participatory_processes) { create_list(:participatory_process, 2, organization: organization) }
          let(:participatory_space_types) do
            [
              { "id" => nil,
                "manifest_name" => "participatory_processes",
                "ids" => [participatory_processes.first.id.to_s] },
              { "id" => nil,
                "manifest_name" => "assemblies",
                "ids" => [] },
              { "id" => nil,
                "manifest_name" => "conferences",
                "ids" => [] },
              { "id" => nil,
                "manifest_name" => "consultations",
                "ids" => [] },
              { "id" => nil,
                "manifest_name" => "initiatives",
                "ids" => [] }
            ]
          end

          let!(:deliverable_users) do
            create_list(:user, 5, :confirmed, organization: organization, newsletter_notifications_at: Time.current)
          end

          before do
            deliverable_users.each do |follower|
              create(:follow, followable: participatory_processes.first, user: follower)
            end
          end

          it_behaves_like "selective newsletter"
        end
      end

      context "when sending to participants" do
        let(:send_to_participants) { true }

        context "when no spaces selected " do
          it "is not valid" do
            expect { command.call }.to broadcast(:invalid)
          end
        end

        context "when spaces selected" do
          let(:participatory_processes) { create_list(:participatory_process, 2, organization: organization) }
          let(:participatory_space_types) do
            [
              { "id" => nil,
                "manifest_name" => "participatory_processes",
                "ids" => [participatory_processes.first.id.to_s] },
              { "id" => nil,
                "manifest_name" => "assemblies",
                "ids" => [] },
              { "id" => nil,
                "manifest_name" => "conferences",
                "ids" => [] },
              { "id" => nil,
                "manifest_name" => "consultations",
                "ids" => [] },
              { "id" => nil,
                "manifest_name" => "initiatives",
                "ids" => [] }
            ]
          end

          let!(:deliverable_users) do
            create_list(:user, 5, :confirmed, organization: organization, newsletter_notifications_at: Time.current)
          end

          let!(:component) { create(:dummy_component, participatory_space: participatory_processes.first, organization: organization) }

          before do
            deliverable_users.each do |participant|
              create(:dummy_resource, component: component, author: participant)
            end
          end

          it_behaves_like "selective newsletter"
        end
      end
    end
  end
end
