# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::PipelineSchedule, feature_category: :continuous_integration do
  let_it_be_with_reload(:project) { create_default(:project) }

  subject { build(:ci_pipeline_schedule) }

  it { is_expected.to belong_to(:project) }
  it { is_expected.to belong_to(:owner) }

  it { is_expected.to have_many(:pipelines).dependent(:nullify) }
  it { is_expected.to have_many(:variables) }

  it { is_expected.to respond_to(:ref) }
  it { is_expected.to respond_to(:cron) }
  it { is_expected.to respond_to(:cron_timezone) }
  it { is_expected.to respond_to(:description) }
  it { is_expected.to respond_to(:next_run_at) }

  it_behaves_like 'includes Limitable concern' do
    subject { build(:ci_pipeline_schedule, project: project) }
  end

  it_behaves_like 'cleanup by a loose foreign key' do
    let!(:parent) { create(:user) }
    let!(:model) { create(:ci_pipeline_schedule, owner: parent) }
  end

  describe 'validations' do
    it 'does not allow invalid cron patterns' do
      pipeline_schedule = build(:ci_pipeline_schedule, cron: '0 0 0 * *')

      expect(pipeline_schedule).not_to be_valid
    end

    it 'does not allow invalid cron patterns' do
      pipeline_schedule = build(:ci_pipeline_schedule, cron_timezone: 'invalid')

      expect(pipeline_schedule).not_to be_valid
    end

    it 'does not allow empty variable key' do
      pipeline_schedule = build(:ci_pipeline_schedule, variables_attributes: [{ secret_value: 'test_value' }])

      expect(pipeline_schedule).not_to be_valid
    end

    context 'when active is false' do
      it 'does not allow nullified ref' do
        pipeline_schedule = build(:ci_pipeline_schedule, :inactive, ref: nil)

        expect(pipeline_schedule).not_to be_valid
      end
    end

    context 'when cron contains trailing whitespaces' do
      it 'strips the attribute' do
        pipeline_schedule = build(:ci_pipeline_schedule, cron: ' 0 0 * * *   ')

        expect(pipeline_schedule).to be_valid
        expect(pipeline_schedule.cron).to eq('0 0 * * *')
      end
    end
  end

  describe '.runnable_schedules' do
    subject { described_class.runnable_schedules }

    let!(:pipeline_schedule) do
      travel_to(1.day.ago) do
        create(:ci_pipeline_schedule, :hourly)
      end
    end

    it 'returns the runnable schedule' do
      is_expected.to eq([pipeline_schedule])
    end

    context 'when there are no runnable schedules' do
      let!(:pipeline_schedule) {}

      it 'returns an empty array' do
        is_expected.to be_empty
      end
    end
  end

  describe '.preloaded' do
    subject { described_class.preloaded }

    before do
      create_list(:ci_pipeline_schedule, 3)
    end

    it 'preloads the associations' do
      subject

      query = ActiveRecord::QueryRecorder.new { subject.map(&:project).each(&:route) }

      expect(query.count).to eq(3)
    end
  end

  describe '.owned_by' do
    let(:user) { create(:user) }
    let!(:owned_pipeline_schedule) { create(:ci_pipeline_schedule, owner: user) }
    let!(:other_pipeline_schedule) { create(:ci_pipeline_schedule) }

    subject { described_class.owned_by(user) }

    it 'returns owned pipeline schedules' do
      is_expected.to eq([owned_pipeline_schedule])
    end
  end

  describe '.for_project' do
    let(:project) { create(:project) }
    let!(:project_pipeline_schedule) { create(:ci_pipeline_schedule, project: project) }
    let!(:other_pipeline_schedule) { create(:ci_pipeline_schedule) }

    subject { described_class.for_project(project) }

    it 'returns pipeline schedule only for project' do
      is_expected.to eq([project_pipeline_schedule])
    end
  end

  describe '#set_next_run_at' do
    let(:now) { Time.zone.local(2021, 3, 2, 1, 0) }
    let(:pipeline_schedule) { create(:ci_pipeline_schedule, cron: "0 1 * * *") }

    it 'calls fallback method next_run_at if there is no plan limit' do
      allow(Settings).to receive(:cron_jobs).and_return({ 'pipeline_schedule_worker' => { 'cron' => "0 1 2 3 *" } })

      travel_to(now) do
        expect(pipeline_schedule).to receive(:calculate_next_run_at).and_call_original

        pipeline_schedule.set_next_run_at

        expect(pipeline_schedule.next_run_at).to eq(Time.zone.local(2022, 3, 2, 1, 0))
      end
    end

    context 'when there are two different pipeline schedules in different time zones' do
      let(:pipeline_schedule_1) { create(:ci_pipeline_schedule, :weekly, cron_timezone: 'Eastern Time (US & Canada)') }
      let(:pipeline_schedule_2) { create(:ci_pipeline_schedule, :weekly, cron_timezone: 'UTC') }

      it 'sets different next_run_at' do
        expect(pipeline_schedule_1.next_run_at).not_to eq(pipeline_schedule_2.next_run_at)
      end
    end
  end

  describe '#schedule_next_run!' do
    let!(:pipeline_schedule) { create(:ci_pipeline_schedule, :nightly) }

    before do
      pipeline_schedule.update_column(:next_run_at, nil)
    end

    it 'updates next_run_at' do
      expect { pipeline_schedule.schedule_next_run! }
        .to change { pipeline_schedule.next_run_at }
    end

    context 'when record is invalid' do
      before do
        allow(pipeline_schedule).to receive(:save!) { raise ActiveRecord::RecordInvalid, pipeline_schedule }
      end

      it 'nullifies the next run at' do
        pipeline_schedule.schedule_next_run!

        expect(pipeline_schedule.next_run_at).to be_nil
      end
    end
  end

  describe '#job_variables' do
    let!(:pipeline_schedule) { create(:ci_pipeline_schedule) }

    let!(:pipeline_schedule_variables) do
      create_list(:ci_pipeline_schedule_variable, 2, pipeline_schedule: pipeline_schedule)
    end

    subject { pipeline_schedule.job_variables }

    before do
      pipeline_schedule.reload
    end

    it { is_expected.to contain_exactly(*pipeline_schedule_variables.map(&:to_runner_variable)) }
  end

  describe '#daily_limit' do
    let(:pipeline_schedule) { build(:ci_pipeline_schedule) }

    subject(:daily_limit) { pipeline_schedule.daily_limit }

    context 'when there is no limit' do
      before do
        create(:plan_limits, :default_plan, ci_daily_pipeline_schedule_triggers: 0)
      end

      it { is_expected.to be_nil }
    end

    context 'when there is a limit' do
      before do
        create(:plan_limits, :default_plan, ci_daily_pipeline_schedule_triggers: 144)
      end

      it { is_expected.to eq(144) }
    end
  end

  describe '#for_tag?' do
    context 'when the target is a tag' do
      before do
        subject.ref = 'refs/tags/v1.0'
      end

      it { expect(subject.for_tag?).to eq(true) }
    end

    context 'when the target is a branch' do
      before do
        subject.ref = 'refs/heads/main'
      end

      it { expect(subject.for_tag?).to eq(false) }
    end

    context 'when there is no ref' do
      before do
        subject.ref = nil
      end

      it { expect(subject.for_tag?).to eq(false) }
    end
  end

  describe '#ref_for_display' do
    context 'when the target is a tag' do
      before do
        subject.ref = 'refs/tags/v1.0'
      end

      it { expect(subject.ref_for_display).to eq('v1.0') }
    end

    context 'when the target is a branch' do
      before do
        subject.ref = 'refs/heads/main'
      end

      it { expect(subject.ref_for_display).to eq('main') }
    end

    context 'when the ref is ambiguous' do
      before do
        subject.ref = 'release-2.8'
      end

      it { expect(subject.ref_for_display).to eq('release-2.8') }
    end

    context 'when there is no ref' do
      before do
        subject.ref = nil
      end

      it { expect(subject.ref_for_display).to eq(nil) }
    end
  end

  describe '#worker_cron' do
    before do
      allow(Settings).to receive(:cron_jobs)
        .and_return({ pipeline_schedule_worker: { cron: "* 1 2 3 4" } }.with_indifferent_access)
    end

    it "returns cron expression set in Settings" do
      expect(subject.worker_cron_expression).to eq("* 1 2 3 4")
    end
  end

  context 'loose foreign key on ci_pipeline_schedules.project_id' do
    it_behaves_like 'cleanup by a loose foreign key' do
      let!(:parent) { create(:project) }
      let!(:model) { create(:ci_pipeline_schedule, project: parent) }
    end
  end

  describe 'before_destroy' do
    let_it_be_with_reload(:pipeline_schedule) { create(:ci_pipeline_schedule, cron: ' 0 0 * * *   ') }
    let_it_be_with_reload(:pipeline) { create(:ci_pipeline, pipeline_schedule: pipeline_schedule) }

    it 'nullifys associated pipelines' do
      expect(pipeline_schedule).to receive(:nullify_dependent_associations_in_batches).and_call_original

      result = pipeline_schedule.destroy

      expect(result).to be_truthy
      expect(pipeline.reload.pipeline_schedule).to be_nil
      expect(described_class.find_by(id: pipeline_schedule.id)).to be_nil
    end
  end
end
